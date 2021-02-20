;;; -*- Mode: Scheme; Character-encoding: utf-8; -*-
;;; Copyright (C) 2005-2020 beingmeta, inc.  All rights reserved.

(in-module 'gpath/ziptools)

(use-module '{ziptools net/mimetable})

(define (ziptools:gpath:get zip (path #f) (aspect #f) (opts #f) (name) (ctype) (encoding))
  (default! ctype (getopt opts 'content-type (guess-mimetype path #f opts)))
  (default! encoding  (getopt opts 'content-encoding (path->encoding path)))
  (cond ((eq? aspect 'exists?) (exists? (zipfs/info zip path)))
	((eq? aspect 'content)
	 (zip/get zip path (or (not ctype) (not (has-prefix ctype "text")))))
	((not (zip/exists? zip path)) #f)
	(else
	 (let* ((charset (and ctype (has-prefix ctype "text")
			      (or (ctype->charset ctype) #t)))
		(w/content (or (eq? aspect #t) (overlaps? aspect 'content)))
		(data (and w/content (zip/get zip realpath (not charset))))
		(content (and data 
			      (if (string? charset)
				  (packet->string content charset)
				  content)))
		(hash (and content (md5 content))))
	   (frame-create #f
	     'gpath (cons zip path) 
	     'gpathstring (glom "ziptools://(" (zip/filename zip) ")/" path)
	     'rootpath path
	     'content (tryif content content)
	     'content-length (length content)
	     'content-type (or ctype {})
	     'charset (if (string? charset) charset (if charset "utf-8" {}))
	     'last-modified (zip/modtime zip realpath)
	     'md5 (tryif hash (packet->base16 hash))
	     'hash (tryif hash hash))))))
(kno/set-handler! zipfile-type ziptools:gpath:get 'gpath:get)
