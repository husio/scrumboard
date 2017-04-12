app.js:
	cd elm; \
	elm make Main.elm --output ../dist/app.js;

app.min.js: app.js
	cd dist; \
	curl -X POST -s --data-urlencode 'input@app.js' https://javascript-minifier.com/raw \
	        > app.min.js

app.min.css:
	cd dist; \
	curl -X POST -s --data-urlencode 'input@app.css' https://cssminifier.com/raw \
		> app.min.css

build: app.min.js app.min.css

elm-watch:
	cd elm; \
	while true; do \
		elm make Main.elm --output ../dist/app.js; \
		inotifywait *.elm > /dev/null; \
	done

devserver:
	DEBUG=true STATIC=./dist rerun github.com/husio/scrumboard
