import jester, asyncdispatch, os, osproc, strutils, json, threadpool, asyncfile, asyncnet, posix, logging, nuuid, tables, httpclient

type
  Config = object
    tmpDir: string
    logFile: string
  
  APIToken = object
    gist: string
  
  ParsedRequest = object
    code: string
    compilationTarget: string

  RequestConfig = object
    tmpDir: string

const configFileName = "conf.json"
const apiTokenFileName = "token.json"

onSignal(SIGABRT):
  ## Handle SIGABRT from systemd
  # Lines printed to stdout will be received by systemd and logged
  # Start with "<severity>" from 0 to 7
  echo "<2>Received SIGABRT"
  quit(1)

var conf = createShared(Config)
let parsedConfig = parseFile(configFileName)
conf.tmpDir = parsedConfig["tmp_dir"].str
conf.logFile = parsedConfig["log_fname"].str

var apiToken = createShared(APIToken)
let parsedAPIToken = parseFile(apiTokenFileName)
apiToken.gist = parsedAPIToken["gist"].str

let fl = newFileLogger(conf.logFile, fmtStr = "$datetime $levelname ")
fl.addHandler

proc respondOnReady(fv: FlowVar[TaintedString], requestConfig: ptr RequestConfig): Future[string] {.async.} =
  while true:
    if fv.isReady:
      echo ^fv
      
      var errorsFile = openAsync("$1/errors.txt" % requestConfig.tmpDir, fmReadWrite)
      var logFile = openAsync("$1/logfile.txt" % requestConfig.tmpDir, fmReadWrite)
      var errors = await errorsFile.readAll()
      var log = await logFile.readAll()
      
      var ret = %* {"compileLog": errors, "log": log}
      
      errorsFile.close()
      logFile.close()
      freeShared(requestConfig)
      return $ret
      

    await sleepAsync(500)

proc prepareAndCompile(code, compilationTarget: string, requestConfig: ptr RequestConfig): TaintedString =
  discard existsOrCreateDir(requestConfig.tmpDir)
  copyFileWithPermissions("./test/script.sh", "$1/script.sh" % requestConfig.tmpDir)
  writeFile("$1/in.nim" % requestConfig.tmpDir, code)

  execProcess("""
    ./docker_timeout.sh 20s -i -t --net=none -v "$1":/usercode virtual_machine /usercode/script.sh in.nim $2
    """ % [requestConfig.tmpDir, compilationTarget]) 

proc createGist(code: string): string =
  let client = newHttpClient()
  
  client.headers = newHttpHeaders([("Content-Type", "application/json" )])
  let body = %*{
    "description": "Snippet from https://play.nim-lang.org",
    "public": true,
    "files": {
      "playground.nim": {
        "content": code
      }
    }
  }
  let resp = client.request("https://api.github.com/gists?client_id=887dc07b67acec87e489&client_secret=$1" % apiToken.gist, httpMethod = HttpPost, body = $body)
  
  let parsedResponse = parseJson(resp.bodyStream, "response.json")
  return parsedResponse.getOrDefault("html_url").str

proc loadGist(gistId: string): string =
  let client = newHttpClient()

  client.headers = newHttpHeaders([("Content-Type", "application/json" )])

  let resp = client.request("https://api.github.com/gists/$1?client_id=887dc07b67acec87e489&client_secret=$2" % [gistId, apiToken.gist], httpMethod = HttpGet)
  
  let parsedResponse = parseJson(resp.bodyStream, "response.json")
  return parsedResponse.getOrDefault("files").fields["playground.nim"].fields["content"].str


proc compile(code, compilationTarget: string, requestConfig: ptr RequestConfig): Future[string] =
  let fv = spawn prepareAndCompile(code, compilationTarget, requestConfig)
  return respondOnReady(fv, requestConfig)

routes:
  get "/gist/@gistId":
    resp(Http200, loadGist(@"gistId"))

  post "/gist":
    var parsedRequest: ParsedRequest
    let parsed = parseJson(request.body)
    if getOrDefault(parsed, "code").isNil:
      resp(Http400)
    parsedRequest = to(parsed, ParsedRequest)
    
    resp(Http200, @[("Access-Control-Allow-Origin", "*"), ("Access-Control-Allow-Methods", "POST")], createGist(parsedRequest.code))
  post "/compile":
    var parsedRequest: ParsedRequest

    if request.params.len > 0:
      if request.params.hasKey("code"):
        parsedRequest.code = request.params["code"]
      if request.params.hasKey("compilationTarget"):
        parsedRequest.compilationTarget = request.params["compilationTarget"]
    else:
      let parsed = parseJson(request.body)
      if getOrDefault(parsed, "code").isNil:
        resp(Http400)
      if getOrDefault(parsed, "compilationTarget").isNil:
        resp(Http400)
      parsedRequest = to(parsed, ParsedRequest)

    let requestConfig = createShared(RequestConfig)
    requestConfig.tmpDir = conf.tmpDir & "/" & generateUUID()
    let compileResult = await compile(parsedRequest.code, parsedRequest.compilationTarget, requestConfig)
    
    resp(Http200, [("Access-Control-Allow-Origin", "*"), ("Access-Control-Allow-Methods", "POST")], compileResult)
    

info "Starting!"
runForever()
freeShared(conf)
freeShared(apiToken)