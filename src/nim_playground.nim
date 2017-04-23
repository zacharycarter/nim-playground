import jester, asyncdispatch, os, osproc, strutils, json, threadpool, asyncfile, asyncnet

proc respondOnReady(fv: FlowVar[TaintedString], r: Response) {.async.} =
  while true:
    if fv.isReady:
      discard ^fv
      
      var errorsFile = openAsync("tmp/errors.txt", fmReadWrite)
      var logFile = openAsync("tmp/logfile.txt", fmReadWrite)
      var errors = await errorsFile.readAll()
      var log = await logFile.readAll()
      
      var ret = %* {"compileLog": errors, "log": log}
      
      errorsFile.close()
      logFile.close()
      
      await r.send(Http200, newStringTable(), $ret)
      r.client.close()
      break

proc prepareAndCompile(code: string): TaintedString =
  let currentDir = getCurrentDir()
  discard existsOrCreateDir("./tmp")
  copyFileWithPermissions("./test/script.sh", "./tmp/script.sh")
  writeFile("./tmp/in.nim", code)

  execProcess("""
    ./docker_timeout.sh 20s -i -t --net=none -v "$1/tmp":/usercode virtual_machine /usercode/script.sh in.nim
    """ % currentDir)

proc compile(resp: Response, code: string) =
  let fv = spawn prepareAndCompile(code)
  asyncCheck respondOnReady(fv, resp)

routes:
  post "/compile":
    if not request.formData.hasKey("code"):
      resp Http400, "code missing from requests' form data."

    response.data.action = TCActionRaw
    response.compile(request.formData["code"].body)

runForever()