#lang racket

(define o (open-output-file "tmp.txt" #:exists 'replace))

(write "hey" o)
(newline o)
(write "wassup" o)
(newline o)
(write "idk" o)

(close-output-port o)