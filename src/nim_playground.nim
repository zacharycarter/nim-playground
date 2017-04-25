import jester, asyncdispatch, os, osproc, strutils, json, threadpool, asyncfile, asyncnet, posix, logging

type
  Config = object
    tmpDir: string
    logFile: string

const configFileName = "conf.json"


onSignal(SIGABRT):
  ## Handle SIGABRT from systemd
  # Lines printed to stdout will be received by systemd and logged
  # Start with "<severity>" from 0 to 7
  echo "<2>Received SIGABRT"
  quit(1)


var conf = cast[ptr Config](allocShared0(sizeof(Config)))
let parsedConfig = parseFile(configFileName)
conf.tmpDir = parsedConfig["tmp_dir"].str
conf.logFile = parsedConfig["log_fname"].str

let fl = newFileLogger(conf.logFile, fmtStr = "$datetime $levelname ")
fl.addHandler

type
  ParsedRequest = object
    code: string

proc respondOnReady(fv: FlowVar[TaintedString]): Future[string] {.async.} =
  while true:
    if fv.isReady:
      echo ^fv
      
      var errorsFile = openAsync("$1/errors.txt" % conf.tmpDir, fmReadWrite)
      var logFile = openAsync("$1/logfile.txt" % conf.tmpDir, fmReadWrite)
      var errors = await errorsFile.readAll()
      var log = await logFile.readAll()
      
      var ret = %* {"compileLog": errors, "log": log}
      
      errorsFile.close()
      logFile.close()

      return $ret
      

    await sleepAsync(500)

proc prepareAndCompile(code: string): TaintedString =
  discard existsOrCreateDir(conf.tmpDir)
  copyFileWithPermissions("./test/script.sh", "$1/script.sh" % conf.tmpDir)
  writeFile("$1/in.nim" % conf.tmpDir, code)

  execProcess("""
    ./docker_timeout.sh 20s -i -t --net=none -v "$1":/usercode virtual_machine /usercode/script.sh in.nim
    """ % conf.tmpDir)

proc compile(resp: Response, code: string): Future[string] =
  let fv = spawn prepareAndCompile(code)
  return respondOnReady(fv)

routes:
  post "/compile":
    let parsed = parseJson(request.body)
    if getOrDefault(parsed, "code").isNil:
      resp(Http400, nil)

    let parsedRequest = to(parsed, ParsedRequest)
    resp(Http200, @[("Access-Control-Allow-Origin", "*"), ("Access-Control-Allow-Methods", "POST")], await response.compile(parsedRequest.code))

info "Starting!"
runForever()
#freeShared(conf)