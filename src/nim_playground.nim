import jester, asyncdispatch, os, osproc, strutils, json, threadpool, asyncfile, asyncnet, posix, logging

const config_file_name = "conf.json"


onSignal(SIGABRT):
  ## Handle SIGABRT from systemd
  # Lines printed to stdout will be received by systemd and logged
  # Start with "<severity>" from 0 to 7
  echo "<2>Received SIGABRT"
  quit(1)


let conf = parseFile(config_file_name)
let fl = newFileLogger(conf["log_fname"].str, fmtStr = "$datetime $levelname ")
fl.addHandler


type
  ParsedRequest = object
    code: string

proc respondOnReady(fv: FlowVar[TaintedString]): Future[string] {.async.} =
  while true:
    if fv.isReady:
      echo ^fv
      
      var errorsFile = openAsync("tmp/errors.txt", fmReadWrite)
      var logFile = openAsync("tmp/logfile.txt", fmReadWrite)
      var errors = await errorsFile.readAll()
      var log = await logFile.readAll()
      
      var ret = %* {"compileLog": errors, "log": log}
      
      errorsFile.close()
      logFile.close()

      return $ret
      

    await sleepAsync(500)

proc prepareAndCompile(code: string): TaintedString =
  let currentDir = getCurrentDir()
  discard existsOrCreateDir("./tmp")
  copyFileWithPermissions("./test/script.sh", "./tmp/script.sh")
  writeFile("./tmp/in.nim", code)

  execProcess("""
    ./docker_timeout.sh 20s -i -t --net=none -v "$1/tmp":/usercode virtual_machine /usercode/script.sh in.nim
    """ % currentDir)

proc compile(resp: Response, code: string): Future[string] =
  let fv = spawn prepareAndCompile(code)
  return respondOnReady(fv)

routes:
  post "/compile":
    info "HERE1"
    let parsed = parseJson(request.body)
    if getOrDefault(parsed, "code").isNil:
      resp(Http400, nil)

    let parsedRequest = to(parsed, ParsedRequest)
    info "HERE2"
    resp(Http200, @[("Access-Control-Allow-Origin", "*")], await response.compile(parsedRequest.code))

info "Starting!"
runForever()