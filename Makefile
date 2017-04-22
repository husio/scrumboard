app.js:
	cd elm; \
	elm make Main.elm --output ../dist/app.js;

app.min.js: app.js
	cd dist; \
	rm -f app.min.js; \
	uglify -s app.js -o app.min.js

app.min.css:
	cd dist; \
	rm -f app.min.css; \
	uglify -c -s app.css -o app.min.css

dist: app.min.js app.min.css

elm-watch:
	cd elm; \
	while true; do \
		elm make Main.elm --output ../dist/app.js; \
		inotifywait *.elm > /dev/null; \
	done

devserver:
	DEBUG=true STATIC=./dist rerun github.com/husio/scrumboard
