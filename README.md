# Jurager/Deployer #

This bash script provides a straightforward method for achieving zero-downtime deployment with various NodeJS frameworks, and it can also automate the deployment process for other types of applications.

## Requirements ##

For reading `deploy.config.json` configuration, additional packages is required.

To install Ubuntu/Debian

```sh
sudo apt-get install jq
```

To install on Fedora/CentOS

```sh
sudo dnf install jq
```

## Installation ##

```sh
curl -fsSL https://raw.githubusercontent.com/Jurager/deployer/master/deployer.sh | sudo tee /usr/local/bin/deployer.sh > /dev/null && sudo chmod +x /usr/local/bin/deployer.sh
```

## Usage ##

In this example we have application written over NuxtJS, serve it using Nginx.

We want to implement green/blue (zero-downtime) deployment on this application.

> [!NOTE]
> We use two applications at once. At the time of deployment, we build the application which is not running. When all deployment task is done, one application is stopped another is starting. At this moment Nginx  switches to another upstream, transparently to user.

First, define the upstream in Nginx with sample configuration

```
upstream backend {
    server 127.0.0.1:3000 fail_timeout=0;
    server 127.0.0.1:3001 fail_timeout=0;
}
```

Then, in server directive, change the location as follows
```
location / {
    proxy_pass                          http://backend; # set the address of the Node.js instance here
    proxy_next_upstream error timeout   invalid_header http_500;
    proxy_connect_timeout               2;
    proxy_set_header Host               $host;
    proxy_set_header X-Real-IP          $remote_addr;
    proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
    proxy_redirect                      off;
    proxy_buffering off;
}
```
Application is running in daemon mode using supervisord with two configurations as follows

example.blue.conf
```
[program:myapp-blue]
directory=/home/myapp/blue/
command=/bin/bash -c 'nuxt start'
user=myapp
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/myapp-blue.log
```

example.green.conf
```
[program:myapp-green]
directory=/home/myapp/green/
command=/bin/bash -c 'nuxt start'
user=myapp
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/myapp-green.log
```

Structure of application will be following:
```
/home/
    /myapp/
        /green/
            myapp.js
        /blue
            myapp.js
        deploy.config.json
``` 

Configuration `deploy.config.json` must be in directory near `green` and `blue`

```json
{
  "current":"green",
  "commands":{
    "prepare":[
      "git pull"
    ],
    "install":[
      "npm i"
    ],
    "build":[
      "npm run build"
    ],
    "restart":[
      "supervisorctl start merchant-#NEXT_COLOR#",
      "supervisorctl stop merchant-#CURRENT_COLOR#"
    ]
  },
  "logging":{
    "enabled":true,
    "file":"deploy.log"
  }
}
```

To list all available commands, use

```shell
deployer.sh -h
Tool used to implement zero downtime deployment.

Syntax: deployer.sh [-i|v|c|h]
Options:
c  Echo current color.
i  Run commands from 'commands.install' group immediately after prepare
v  Print version.
```

To run the deployment process, run following command in directory with configuration, and wait for process to complete

```shell
cd /home/myapp && deployer.sh
```

## License

This package is open-sourced software licensed under the [MIT license](LICENSE.md).
