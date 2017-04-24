Work in progress.

# Run locally

Run redis instance. If using docker:


    docker run -it --rm  -p 6379:6379 redis


OAuth authentication is required. Unless you want to [register your own
   GitHub OAuth application](https://github.com/settings/applications/new),
   add following line to your `/etc/hosts` file:


    127.0.0.1  scrumboard.dev


Run Go server (`make devserver` requires
   [`rerun`](https://github.com/skelterjohn/rerun)):


    DEBUG=true STATIC=./dist go run main.go


Go to http://scrumboard.dev:8080



# Demo

[Demo](https://scrumbored.herokuapp.com/) (requires GitHub authentication).

# Screenshots

![](http://i.imgur.com/GAt7SAv.png)
![](http://i.imgur.com/HqcmpJC.png)
