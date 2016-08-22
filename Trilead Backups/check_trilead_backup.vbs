'* create an XML DOM
Set xmlDoc = _
	CreateObject("Microsoft.XMLDOM")

'* load xml into memory
xmlDoc.Async = "False"
xmlDoc.Load("C:\ProgramData\Trilead\VMX\VMXTaskHistory.xml")

'* select all nodes with matching server names
strServerName = WScript.Arguments(0)
Set colNodes = xmlDoc.selectNodes _
	("//TaskResults/ScheduledTaskResult" & _
	"[@Name = '" + strServerName + "']")

'* get the most recent time
intMaxTime = 0
For Each objNode in colNodes
	intCurrentTime = objNode.Attributes. _
		getNamedItem("StartTime").Text
	If intCurrentTime > intMaxTime Then
		intMaxTime = intCurrentTime
	End If
Next
'* get the most recent node
Set objNode = xmlDoc.selectSingleNode _
	("//TaskResults/ScheduledTaskResult" & _
	"[@Name = '" + strServerName + "']" & _
	"[@StartTime = '" + intMaxTime + "']")

'* save the task's status code for proliferation
intStatusCode = CInt(objNode.Attributes. _
	getNamedItem("ResultStatusCode").Text)
'* print the status code for zabbix
WScript.Echo intStatusCode
