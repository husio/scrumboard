app.js:
	cd elm; \
	elm make Main.elm --output ../static/app.js;

app.min.js: app.js
	cd static; \
	curl -X POST -s --data-urlencode 'input@app.js' https://javascript-minifier.com/raw \
	        > app.min.js

elm-watch:
	cd elm; \
	while true; do \
		elm make Main.elm --output ../static/app.js; \
		inotifywait *.elm > /dev/null; \
	done


devserver:
	DEBUG=true STATIC=./static rerun github.com/husio/scrumboard/server
