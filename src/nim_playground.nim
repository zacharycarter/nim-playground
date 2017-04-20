import jester, asyncdispatch, os, osproc, strutils, threadpool

proc compile(code: string): string =
  let currentDir = getCurrentDir()
  createDir("./tmp")
  copyFileWithPermissions("./test/script.sh", "./tmp/script.sh")
  writeFile("./tmp/in.nim", code)
  let p = spawn execProcess("""
    ./docker_timeout.sh 20s -i -t -v "$1/tmp":/usercode virtual_machine /usercode/script.sh in.nim
    """ % currentDir)
  assert ^p == ""
  result = readFile("tmp/logfile.txt")
  removeDir("./tmp")

routes:
  post "/compile":
    if not request.formData.hasKey("code"):
      resp Http400, "code missing from requests' form data."
    
    resp Http200, compile(request.formData["code"].body)

runForever()