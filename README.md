This is a hacky attempt to take the jupyter (aka ipython) front end code and use it outside of the notebook context, with a lot of help from tmpnb.

## Front End Use

```
new Thebe(options)

```

Options

```
    default_options:
      # jquery selector for elements we want to make runnable 
      selector: 'pre[data-executable]'
      # the url of either a tmnb server or a notebook server
      # if it contains "spawn/", assume it's a tmpnb server
      # otherwise assume it's a notebook url
      url: 'http://192.168.59.103:8000/spawn/'
      # set to false to not add controls to the page
      prepend_controls_to: 'html'
      # Automatically load necessary css for codemirror and jquery ui
      load_css: true
      # Automatically load mathjax js
      load_mathjax: true
      # show messages from .log
      debug: true
```



## Developing the Front End
Most of the actual development takes place in `static/main.coffee`. I've tried to make as few changes to the rest of the jupyter front end as possible, but there were some cases where it was unavoidable (see #2) for more info on this.

After making a change to the javascript in `static/`, you'll need to recompile it to see your changes in `built.html` or to use it in production. `index.html` will reflect your changes that last `r.js` step.

```
npm install -g requirejs
npm install -g coffee-script
coffee -cbm .
cd static
r.js -o build.js baseUrl=. name=almond include=main out=main-built.js 

```

## Run tmnb Locally

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