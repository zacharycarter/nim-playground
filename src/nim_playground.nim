import jester, asyncdispatch, os, osproc, strutils, json, threadpool, asyncfile, asyncnet

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
    echo request.body
    let parsed = parseJson(request.body)
    if getOrDefault(parsed, "code").isNil:
      resp(Http400, nil)

    let parsedRequest = to(parsed, ParsedRequest)

    resp(Http200, @[("Access-Control-Allow-Origin", "*")], await response.compile(parsedRequest.code))

runForever()