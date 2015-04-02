This is a hacky attempt to take the jupyter (aka ipython) front end code and use it outside of the notebook context, with a lot of help from tmpnb.


## Front end

After making a change to the javascript in `static/`, you'll need to recompile it to see your changes in `built.html` or to use it in production.

```
npm install -g requirejs
npm install -g coffee-script
coffee -cbm .
cd static
r.js -o build.js baseUrl=. name=almond include=main out=main-built.js 

```

## Run The Servers Locally

First, you need docker (and boot2docker if you're on a OS X) installed. 

Pull the images.

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