import jester, asyncdispatch, os, osproc, strutils, json, threadpool, asyncfile, asyncnet, posix, logging, nuuid, tables

type
  Config = object
    tmpDir: string
    logFile: string
  
  ParsedRequest = object
    code: string

  RequestConfig = object
    tmpDir: string

const configFileName = "conf.json"

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

proc prepareAndCompile(code: string, requestConfig: ptr RequestConfig): TaintedString =
  discard existsOrCreateDir(requestConfig.tmpDir)
  copyFileWithPermissions("./test/script.sh", "$1/script.sh" % requestConfig.tmpDir)
  writeFile("$1/in.nim" % requestConfig.tmpDir, code)

  execProcess("""
    ./docker_timeout.sh 20s -i -t --net=none -v "$1":/usercode virtual_machine /usercode/script.sh in.nim
    """ % requestConfig.tmpDir)

proc compile(resp: Response, code: string, requestConfig: ptr RequestConfig): Future[string] =
  echo requestConfig.tmpDir
  let fv = spawn prepareAndCompile(code, requestConfig)
  return respondOnReady(fv, requestConfig)

routes:
  post "/compile":
    var parsedRequest: ParsedRequest

    if request.params.len > 0:
      if request.params.hasKey("code"):
        parsedRequest.code = request.params["code"]
        echo parsedRequest.code
    else:
      let parsed = parseJson(request.body)
      if getOrDefault(parsed, "code").isNil:
        resp(Http400, nil)
      parsedRequest = to(parsed, ParsedRequest)

    let requestConfig = createShared(RequestConfig)
    requestConfig.tmpDir = conf.tmpDir & "/" & generateUUID()
    let result = await response.compile(parsedRequest.code, requestConfig)
    
    resp(Http200, @[("Access-Control-Allow-Origin", "*"), ("Access-Control-Allow-Methods", "POST")], result)
    

info "Starting!"
runForever()
freeShared(conf)