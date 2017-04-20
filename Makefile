app.js:
	cd elm; \
	elm make Main.elm --output ../dist/app.js;

app.min.js: app.js
	cd dist; \
	uglify -s dist/app.js -o dist/app.min.js

app.min.css:
	cd dist; \
	uglify -s dist/app.css -o dist/app.min.css

dist: app.min.js app.min.css

elm-watch:
	cd elm; \
	while true; do \
		elm make Main.elm --output ../dist/app.js; \
		inotifywait *.elm > /dev/null; \
	done

devserver:
	DEBUG=true STATIC=./dist rerun github.com/husio/scrumboard
