`Thebe` takes the [Jupyter](https://github.com/jupyter/) (formerly [ipython](https://github.com/ipython/ipython)) front end, and make it work outside of the notebook context.

## What? Why?
In short, this is an easy way to let users on a web page run code examples on a server. 

Three things are required:

1. A server, either a [tmpnb](https://github.com/zischwartz/tmpnb) server, for lots of users, or simple an ipython notebook server.
1. A web page with some code examples
1. A script tag in the page that includes the compiled javascript of `Thebe`, which is in this repo at `static/main-built.js`

Also, [Thebe is a moon of Jupiter](http://en.wikipedia.org/wiki/Thebe_%28moon%29) in case you were wondering. Naming things is hard.

## Front End Use
Include the `Thebe` script like so:

```
<script src="https://rawgit.com/oreillymedia/thebe/master/static/main-built.js" type="text/javascript" charset="utf-8"></script>
```

When loaded, this will automatically instantiate `Thebe` with the default options. Any `pre` tags with the `data-executable` attribute will be turned into editable, runnable examples, and a run button will be added for each. Once run is clicked, `Thebe` will try to connect to our testing tmpnb server, start the kernel, and execute the code in that example.


## Thebe Options
You can override these when you instantiate: `Thebe(options)`

    default_options:
      # jquery selector for elements we want to make runnable 
      selector: 'pre[data-executable]'
      # the url of either a tmnb server or a notebook server
      # if it contains "spawn/", assume it's a tmpnb server
      # otherwise assume it's a notebook url
      url: 'http://192.168.59.103:8000/spawn/'
      # set to false to prevent kernel_controls from being added
      append_kernel_controls_to: 'body'
      # Automatically inject basic default css we need
      inject_css: true
      # Automatically load other necessary css (jquery ui)
      load_css: true
      # Automatically load mathjax js
      load_mathjax: true
      # show messages from .log()
      debug: false

# Run Locally (Simple)
The easiest way to get this running locally is to simply set the `url` option to the url of an running ipython notebook.

After installing ipython, run it like so:

    ipython notebook  --NotebookApp.allow_origin=* --no-browser

Which defaults to running at http://localhost:8888/, and should tell you that.

Now, in your javascript, after docready, instantiate Thebe with that url:

    thebe = new Thebe({url:http://localhost:8888/, selector:'pre'})


## Developing the Front End
Most of the actual development takes place in `static/main.coffee`. I've tried to make as few changes to the rest of the jupyter front end as possible, but there were some cases where it was unavoidable (see #2 for more info on this).

After making a change to the javascript in `static/`, you'll need to recompile it to see your changes in `built.html` or to use it in production. `index.html` will reflect your changes that last `r.js` step.

```
npm install -g requirejs
npm install -g coffee-script
coffee -cbm .
cd static
r.js -o build.js baseUrl=. name=almond include=main out=main-built.js 

```

## Run `tmnb` Locally

First, you need docker (and boot2docker if you're on a OS X) installed. 

Pull the images. [This version](https://github.com/zischwartz/tmpnb) is a slightly different fork of the [main repo](https://github.com/jupyter/tmpnb), which adds an options for `cors`, which we need for this to work.

```
docker pull jupyter/configurable-http-proxy
docker pull zischwartz/tmpnb 
docker pull zischwartz/scipyserver
```

Then startup the docker containers for the proxy and tmpnb like so:

```
export TOKEN=$( head -c 30 /dev/urandom | xxd -p )

docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN --name=proxy jupyter/configurable-http-proxy --default-target http://127.0.0.1:9999

docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN -v /var/run/docker.sock:/docker.sock zischwartz/tmpnb python orchestrate.py --image="zischwartz/scipyserver" --allow_origin="*" --command="ipython3 notebook --no-browser --port {port} --ip=* --NotebookApp.allow_origin=* --NotebookApp.base_url={base_path}" --cull-timeout=300 --cull_period=60
```

Next, start a normal server in this directory

```
python -m SimpleHTTPServer

```

and visit it at [localhost:8000](http://localhost:8000) and [localhost:8000/built.html](http://localhost:8000/built.html)