#lang racket/base
(require (for-syntax racket/base
                     syntax/parse/pre
                     enforest/hier-name-parse
                     "name-path-op.rkt")
         syntax/parse/pre
         "pack.rkt"
         "syntax-class.rkt"
         (submod "syntax-class.rkt" for-quasiquote)
         (only-in "annotation.rkt"
                  ::)
         "pattern-variable.rkt"
         "syntax-binding.rkt"
         "name-root-ref.rkt"
         "parens.rkt")

(provide (for-space rhombus/syntax_binding
                    _
                    #%parens
                    ::
                    &&
                    \|\|
                    #%block))

(module+ for-quasiquote
  (provide (for-syntax identifier-as-pattern-syntax)))

;; `#%quotes` is impemented in 'quasiquote.rkt", because it recurs as
;; nested quasiquote matching

(define-for-syntax (identifier-as-pattern-syntax id kind
                                                 #:result [result list]
                                                 #:pattern-variable [pattern-variable list])
  (define-values (pack* unpack*)
    (case kind
      [(term) (values #'pack-term* #'unpack-term*)]
      [(group) (values #'pack-group* #'unpack-group*)]
      [(multi block) (values #'pack-tagged-multi* #'unpack-multi-as-term*)]))
  (let* ([temps (generate-temporaries (list id id))]
         [temp1 (car temps)]
         [temp2 (cadr temps)])
    (result temp1
            (list #`[#,temp2 (#,pack* (syntax #,temp1) 0)])
            (list #`[#,id (make-pattern-variable-syntax (quote-syntax #,id)
                                                        (quote-syntax #,temp2)
                                                        (quote-syntax #,unpack*)
                                                        0
                                                        #f
                                                        (hasheq))])
            (list (pattern-variable id temp2 0 unpack*)))))

(define-syntax-binding-syntax _
  (syntax-binding-prefix-operator
   #'_
   null
   'macro
   (lambda (stx)
     (syntax-parse stx
       [(form-id . tail)
        (values #`(#,(syntax/loc #'form-id _) () () ())
                #'tail)]))))

(define-syntax-binding-syntax #%parens
  (syntax-binding-prefix-operator
   #'#%parens
   null
   'macro
   (lambda (stx)
     (syntax-parse stx
       [(_ (parens g::syntax-binding) . tail)
        (values #'g.parsed
                #'tail)]))))

(define-syntax-binding-syntax ::
  (syntax-binding-infix-operator
   #'::
   null
   'macro
   (lambda (form1 stx)
     (unless (identifier? form1)
       (raise-syntax-error #f
                           "preceding term must be an identifier"
                           (syntax-parse stx
                             [(colons . _) #'colons])))
     (define (build stx-class only-attribute-name)
       (with-syntax ([id form1])
         (define rsc (syntax-local-value (in-syntax-class-space stx-class) (lambda () #f)))
         (define (compat pack* unpack*)
           (define sc (rhombus-syntax-class-class rsc))
           (define temp0-id (car (generate-temporaries (list #'id))))
           (define temp-id (car (generate-temporaries (list #'id))))
           (define-values (attribute-bindings attribute-mappings)
             (for/lists (bindings mappings) ([name+depth (in-list (rhombus-syntax-class-attributes rsc))]
                                             [temp-attr (in-list (generate-temporaries
                                                                  (map car (rhombus-syntax-class-attributes rsc))))]
                                             #:do [(define name (car name+depth))]
                                             #:when (or (not only-attribute-name)
                                                        (eq? name (syntax-e only-attribute-name))))
               (define depth (cdr name+depth))
               (define id-with-attr
                 (datum->syntax temp0-id (string->symbol (format "~a.~a" (syntax-e temp0-id) name))))
               (values #`[#,temp-attr (pack-term*
                                       (syntax #,(let loop ([t id-with-attr] [depth depth])
                                                   (if (zero? depth)
                                                       t
                                                       (loop #`(#,t #,(quote-syntax ...)) (sub1 depth)))))
                                       #,depth)]
                       (cons name (cons temp-attr depth)))))
           (cond
             [only-attribute-name
              (unless (pair? attribute-bindings)
                (raise-syntax-error #f
                                    "not an attribute of the syntax class"
                                    only-attribute-name))
              (define temp-attr (cadar attribute-mappings))
              (define depth (cddar attribute-mappings))
              #`(#,(if sc
                       #`(~var #,temp0-id #,sc)
                       temp0-id)
                 #,attribute-bindings
                 #,(list #`[id (make-pattern-variable-syntax
                                (quote-syntax id)
                                (quote-syntax #,temp-attr)
                                (quote-syntax #,unpack*)
                                #,depth
                                #f
                                #hasheq())])
                 #,(list (list #'id temp-attr depth unpack*)))]
             [else
              (define pack-depth (if (rhombus-syntax-class-splicing? rsc) 1 0))
              #`(#,(if sc
                       #`(~var #,temp0-id #,sc)
                       temp0-id)
                 #,(cons #`[#,temp-id (#,pack* (syntax #,temp0-id) #,pack-depth)] attribute-bindings)
                 #,(list #`[id (make-pattern-variable-syntax
                                (quote-syntax id)
                                (quote-syntax #,temp-id)
                                (quote-syntax #,unpack*)
                                #,pack-depth
                                #,(rhombus-syntax-class-splicing? rsc)
                                (hasheq #,@(apply append (for/list ([b (in-list attribute-mappings)])
                                                           (list #`(quote #,(car b))
                                                                 #`(syntax-class-attribute (quote-syntax #,(cadr b))
                                                                                           #,(cddr b)))))))])
                 #,(list (list #'id temp-id pack-depth unpack*)))]))
         (define (incompat)
           (raise-syntax-error #f
                               "syntax class incompatible with this context"
                               stx-class))
         (define (retry) #'#f)
         (define kind (current-syntax-binding-kind))
         (cond
           [(not (rhombus-syntax-class? rsc))
            (raise-syntax-error #f
                                "not bound as a syntax class"
                                stx-class)]
           [(eq? (rhombus-syntax-class-kind rsc) 'term)
            (cond
              [(not (eq? kind 'term)) (retry)]
              [else (compat #'pack-term* #'unpack-term*)])]
           [(eq? (rhombus-syntax-class-kind rsc) 'group)
            (cond
              [(eq? kind 'term) (incompat)]
              [(not (eq? kind 'group)) (retry)]
              [else (compat #'pack-group* #'unpack-group* )])]
           [(eq? (rhombus-syntax-class-kind rsc) 'multi)
            (cond
              [(or (eq? kind 'multi) (eq? kind 'block))
               (compat #'pack-tagged-multi* #'unpack-multi-as-term*)]
              [else (incompat)])]
           [(eq? (rhombus-syntax-class-kind rsc) 'block)
            (cond
              [(eq? kind 'block)
               (compat #'pack-block* #'unpack-multi-as-term*)]
              [else (incompat)])]
           [else
            (error "unrecognized kind" kind)])))
     (syntax-parse stx
       [(_ . rest)
        #:with (~var stx-class-hier (:hier-name-seq in-syntax-class-space name-path-op name-root-ref)) #'rest
        #:with tail #'stx-class-hier.tail
        (syntax-parse #'tail
          #:datum-literals (group)
          [((_::block (group field:identifier)))
           (values (build #'stx-class-hier.name #'field) #'())]
          [((_::block . _))
           (raise-syntax-error #f "expected an attribute identifier in block" stx)]
          [_
           (values (build #'stx-class-hier.name #f) #'tail)])]))
   'none))

(define-for-syntax (normalize-id form)
  (if (identifier? form)
      (identifier-as-pattern-syntax form (current-syntax-binding-kind))
      form))

(define-for-syntax (norm-seq pat like-pat)
  (syntax-parse pat
    [((~datum ~seq) . _) pat]
    [_ (syntax-parse like-pat
         [((~datum ~seq) . _) #`(~seq #,pat)]
         [_ pat])]))

(define-syntax-binding-syntax &&
  (syntax-binding-infix-operator
   #'&&
   null
   'automatic
   (lambda (form1 form2 stx)
     (syntax-parse (normalize-id form1)
       [#f #'#f]
       [(pat1 (idr1 ...) (sidr1 ...) (var1 ...))
        (syntax-parse (normalize-id form2)
          [#f #'#f]
          [(pat2 idrs2 sidrs2 vars2)
           #`((~and #,(norm-seq #'pat1 #'pat2) #,(norm-seq #'pat2 #'pat1))
              (idr1 ... . idrs2)
              (sidr1 ... . sidrs2)
              (var1 ... . vars2))])]))
   'left))

(define-syntax-binding-syntax \|\|
  (syntax-binding-infix-operator
   #'\|\|
   null
   'automatic
   (lambda (form1 form2 stx)
     (syntax-parse (normalize-id form1)
       [#f #'#f]
       [(pat1 idrs1 sidrs1 vars1)
        (syntax-parse (normalize-id form2)
          [#f #'#f]
          [(pat2 idrs2 sidrs2 vars2)
           #`((~or #,(norm-seq #'pat1 #'pat2)
                   #,(norm-seq #'pat2 #'pat1))
              ()
              ()
              ())])]))
   'left))

(define-syntax-binding-syntax #%block
  (syntax-binding-prefix-operator
   #'#%body
   '((default . stronger))
   'macro
   (lambda (stxes)
     (syntax-parse stxes
       [(_ b)
        (raise-syntax-error #f
                            "not allowed as a syntax binding by itself"
                            #'b)]))))