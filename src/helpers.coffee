fs = require "fs"
log = require('printit')()
request = require("request-json-light")
exec = require('child_process').exec
path = require 'path'

try
    config = JSON.parse(fs.readFileSync '/etc/cozy/controller.json', 'utf8')
couchdbHost = process.env.COUCH_HOST or config?.env?['data-system']?.COUCH_HOST  or 'localhost'
couchdbPort = process.env.COUCH_PORT or config?.env?['data-system']?.COUCH_PORT  or '5984'
postfixHost = process.env.POSTFIX_HOST or 'localhost'
postfixPort = process.env.POSTFIX_PORT or '25'
controllerPort = process.env.CONTROLLER_PORT or '9002'
module.exports.dbName = process.env.DB_NAME or config?.env?['data-system']?.DB_NAME  or 'cozy'

couchUrl = "http://#{couchdbHost}:#{couchdbPort}/"
dataSystemUrl = "http://localhost:9101/"
controllerOptions = {
    host: "localhost",
    port: controllerPort
}
homeUrl = "http://localhost:9103/"
proxyUrl = "http://localhost:9104/"
postfixUrl = "http://#{postfixHost}:#{postfixPort}/"
ControllerClient = require("cozy-clients").ControllerClient


# Read Controller auth token from token file located in /etc/cozy/stack.token .
readToken = (file) ->
    try
        token = fs.readFileSync file, 'utf8'
        token = token.split('\n')[0]
        return token
    catch err
        log.info """
Cannot get Cozy credentials. Are you sure you have the rights to access to:
/etc/cozy/stack.token ?
"""
        return null

# Get Controller auth token from token file. If it can't find token in
# expected folder it looks for in the location of previous controller version
# (backward compatibility).
getToken = module.exports.getToken = ->
    # New controller
    if fs.existsSync '/etc/cozy/stack.token'
        return readToken '/etc/cozy/stack.token'
    else
        # Old controller
        if fs.existsSync '/etc/cozy/controller.token'
            return readToken '/etc/cozy/controller.token'
        else
            return null


getAuthCouchdb = module.exports.getAuthCouchdb = (exit=true) ->
    try
        data = fs.readFileSync '/etc/cozy/couchdb.login', 'utf8', (err, data) ->
        username = data.split('\n')[0]
        password = data.split('\n')[1]
        return [username, password]
    catch error
        log.error """
Cannot read database credentials in /etc/cozy/couchdb.login.
"""
        if exit
            process.exit 1
        else
            return ['', '']

module.exports.makeError = (err, body) ->
    if err?
        return new Error(err)
    else if body?
        if body.msg
            return new Error(body.msg)
        else if body.message
            return new Error(body.message)
        else if body.error
            return new Error(body.error)

module.exports.logError = (err, msg, doExit = true) ->
    log.error "An error occured:"
    log.error msg if msg?
    log.raw err

    if doExit
        process.exit(1)

module.exports.handleError = (err, body, msg) ->
    log.error "An error occured:"
    log.raw err if err
    log.raw msg
    if body?
        if body.msg?
            log.raw body.msg
        else if body.error?
            log.raw body.error.message if body.error.message?
            log.raw body.message if body.message?
            log.raw body.error.result if body.error.result?
            log.raw "Request error code #{body.error.code}" if body.error.code?
            log.raw body.error.blame if body.error.blame?
            log.raw body.error if typeof body.error is "string"
        else log.raw body
    process.exit 1


controllerOptions.token = getToken()
module.exports.clients =
    'home': request.newClient homeUrl
    'couch': request.newClient couchUrl
    'ds': request.newClient dataSystemUrl
    'data-system': request.newClient dataSystemUrl
    'proxy': request.newClient proxyUrl
    'controller': new ControllerClient(controllerOptions)
    'postfix': request.newClient postfixUrl
    'mta': request.newClient postfixUrl



module.exports.retrieveManifestFromDisk = (app, callback) ->

    # Define path
    basePath =  path.join '/usr/local/cozy/apps', app
    manifestPath = path.join basePath, 'package.json'

    # Retrieve manifest from package.json
    manifest = JSON.parse(fs.readFileSync manifestPath, 'utf8')

    # If our app is an app installed via NPM, we get the manifest from
    # the subfolder generated by NPM.
    if manifest.name is 'cozy-controller-fake-package.json'

        moduleDirectory = path.join basePath, 'node_modules'
        if app in [
            'data-system',
            'home',
            'proxy',
            'calendar',
            'contacts',
            'emails',
            'files'
        ]
            fullAppName = "cozy-#{app}"
        else
            fullAppName = app

        manifestPath =  path.join moduleDirectory, fullAppName, 'package.json'
        manifest = JSON.parse(fs.readFileSync manifestPath, 'utf8')
        manifest.package = manifest.name

        callback null, manifest

    else
        # Retrieve url for git config
        command = "cd #{basePath} && git config --get remote.origin.url"
        exec command, (err, body) ->
            return callback err if err?
            manifest.repository =
                type: 'git'
                url: body.replace '\n', ''

            # Retrieve branch from git config
            command = "cd #{basePath} && git rev-parse --abbrev-ref HEAD"
            exec command, (err, body) ->
                return callback err if err?
                manifest.repository.branch = body.replace '\n', ''
                callback null, manifest

