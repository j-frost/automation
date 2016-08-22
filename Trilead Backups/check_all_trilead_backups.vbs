'* create an XML DOM
Set xmlDoc = _
	CreateObject("Microsoft.XMLDOM")

'* load xml into memory
xmlDoc.Async = "False"
xmlDoc.Load("C:\ProgramData\Trilead\VMX\VMXTaskHistory.xml")

'* find all unique server names and put them into dynamic array
Dim arrServerNames()
ReDim Preserve arrServerNames(-1)
Set colNodes = xmlDoc.selectNodes _
	("//TaskResults/ScheduledTaskResult")
For Each objNode in colNodes
	strCurrentName = objNode.Attributes. _
		getNamedItem("Name").Text
	For Each strServerName in arrServerNames
		If strCurrentName = strServerName Then
			boolFound = True
		End If
	Next
	If NOT boolFound Then
		intNewSize = UBound(arrServerNames) + 1
		ReDim Preserve arrServerNames(intNewSize)
		arrServerNames(intNewSize) = strCurrentName
	End If
Next

'* prepare a results array
Dim arrDetails()
ReDim Preserve arrDetails(0)
'* iterate over all servers
For Each strServerName in arrServerNames
	'* select all nodes with matching server names
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
	intStatusCode = CInt(objNode.Attributes. _
		getNamedItem("ResultStatusCode").Text)
	If intStatusCode <> 0 Then
		intSize = UBound(arrDetails) + 1
		ReDim Preserve arrDetails(intSize)
		arrDetails(intSize) = objNode.Attributes. _
			getNamedItem("Detail").Text
	End If
Next

'* print the status code for zabbix
If UBound(arrDetails) = 0 Then
	WScript.Echo("no error")
Else
	For Each strErrorMessage in arrDetails
		WScript.Echo(strErrorMessage)
	Next
End If
