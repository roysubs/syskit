' By using VBScript, we can make the handover to send-magnet-to-qb.ps1 windowless.
' i.e. The magnet association calls the .vbs, which then calls the .ps1 
' This is not possible if we target send-magnet-to-qb.ps1 directly.
Dim magnetLink
magnetLink = WScript.Arguments(0)
Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\roysu\send-magnet-to-qb.ps1"" """ & magnetLink & """", 0, False

' Could also add -NoProfile possibly for slightly faster execution time, in addition to the above.
'    "powershell.exe -NoProfile
