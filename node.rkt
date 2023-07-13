#lang racket

(provide
 (all-defined-out))

(define d-rt
    (hash 0 8880
          1 8881
          2 8882
          3 8883))

(define hi 'no)

(require json)

(define (qs id)
  (make-and-start-node id d-rt (current-input-port)))

(define (commit ns msg)
  (define out (node-state-commit-port ns))
  (write-json msg out)
  (newline out)
  (flush-output out))

(define (log ns msg)
  (define out (node-state-log-port ns))
  (write-json msg out)
  (newline out)
  (flush-output out))

(struct node-state [id routing-table msgs-to-be-sent log-port commit-port input-port listener] #:transparent)

(define (node-state:make id rt input-port)
  (define log-file (string-append (number->string id) "-log.txt"))
  (define commit-file (string-append (number->string id) "-commit.txt"))
  (define listener (tcp-listen (hash-ref rt id)))
  (node-state id rt '()
              (open-output-file log-file #:exists 'replace)
              (open-output-file commit-file #:exists 'replace)
              input-port
              listener))

(define (clear-file file)
  (with-output-to-file file
    (λ () (println ""))
      #:exists 'replace))

(define (node-state:add-msg-to-be-sent ns msg)
  (struct-copy node-state ns
               [msgs-to-be-sent (append (node-state-msgs-to-be-sent ns) (list msg))]))

(define (node-state:get-id-port ns id)
  (hash-ref (node-state-routing-table ns) id))

(define (node-state:get-self-port ns)
  (node-state:get-id-port ns (node-state-id ns)))

(define (node-state:get-top-message ns)
  (first (node-state-msgs-to-be-sent ns)))

(define (node-state:remove-top-message ns)
  (struct-copy node-state ns
               [msgs-to-be-sent (rest (node-state-msgs-to-be-sent ns))]))

(define (node-state:msgs-to-be-sent? ns)
  (not (equal? 0 (length (node-state-msgs-to-be-sent ns)))))

(define (make-and-start-node id rt ip)
  (parameterize ([current-custodian (make-custodian)])
    (define ns (node-state:make id rt ip))
    (wait-for-user-input ns)))

(define (wait-for-user-input state)
  (println "waiting for user input: ")
  
  (define result
    (with-handlers ([exn:fail? (λ (e) (begin
                                        (display e)
                                        (println "invalid input!")
                                        (read (node-state-input-port state))
                                        #f))])
      (sync/timeout/enable-break
       5
       (handle-evt
        (node-state-input-port state)
        (λ (p)
          (let ([input (read-json p)])
            (cond
              [(equal? "shutdown" input) 'shutdown]
              [(msg? input) (node-state:add-msg-to-be-sent state input)])))))))
  
  (if (equal? result 'shutdown)
      (custodian-shutdown-all (current-custodian))
      (if result
          (listen-on-network result)
          (listen-on-network state))))

(define (msg? v)
  (println (hash? v))
  (println (hash-has-key? v 'id))
  (println v)
  (and
   (hash? v)
   (or (hash-has-key? v 'data)
       (hash-has-key? v 'id))))

(define (listen-on-network state)
  (println "waiting for network connection")
  (define result
    (sync/timeout/enable-break
     2
     (handle-evt
      (node-state-listener state)
      (λ (listenr)
        (define-values (in out) (tcp-accept listenr))
        (define recv (read-json in))
        (log state "received: ")
        (log state recv)
        (node-state:add-msg-to-be-sent state recv)))))
  (if result
      (send-to-be-sent result)
      (send-to-be-sent state)))

(define (msg-reached-destination? msg)
  (hash-has-key? msg 'data))

(define (send-to-be-sent start-state)
  (println "starting send phase")
  (display (node-state-msgs-to-be-sent start-state))
  (println "")
  (let sending-loop ([state start-state])
    (call-with-exception-handler
     (λ (e) (begin (display e)
                   (custodian-shutdown-all (current-custodian))))
     (thunk
      (if (node-state:msgs-to-be-sent? state)
          (begin
            (let ([top-msg (node-state:get-top-message state)])
              (if (msg-reached-destination? top-msg)
                  (begin
                    (commit state top-msg)
                    (sending-loop (node-state:remove-top-message state)))
                  (sending-loop (send-msg-to-next top-msg state)))))
            (wait-for-user-input state))))))

(define (next-step msg)
  (hash-ref msg 'id))

(define (send-msg-to-next msg state)
  (define-values (in out) (tcp-connect "127.0.0.1" (node-state:get-id-port state (next-step msg))))
  (log state "sending: ")
  (log state (hash-ref msg 'rest))
  (write-json (hash-ref msg 'rest) out)
  (close-output-port out)
  (close-input-port in)
  (node-state:remove-top-message state))
     
      