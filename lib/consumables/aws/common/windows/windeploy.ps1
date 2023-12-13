# Rename computer based on the instance id

Start-Transcript -IncludeInvocationHeader -Path "$ENV:SystemRoot\Temp\rename.log" -Append
$SsmPlatformSecretPath=""
$Userdata = "" 

# Improve windeploy.ps1 script to resolve http://169.254.169.254 correctly
# https://jira.qantas.com.au/browse/QCP-2797

$UserdataCount = 0
while($UserdataCount -le 12) {
    try {
        $Userdata = (Invoke-RestMethod -uri "http://169.254.169.254/latest/user-data")
        Write-Output "Successfully retrieve user-data: $Userdata"
        break
    } catch {
        write-output "Unable to retrieve user-data..."
        start-sleep 5
        $UserdataCount = $UserdataCount + 1
    }
}

foreach($Line in $Userdata)
{
   $Matched = $Line -match "SsmPlatformSecretPath=""(?<content>.*)"""
}

if($Matched){
   $SsmPlatformSecretPath=$Matches['content']
}

function Get-ProsperoPath {
  return "C:\\Windows\\Temp\\Pipeline.Prospero.ps1"
}

try {

    $prosperoPath =  Get-ProsperoPath
    Write-Output "Including Prospero: $prosperoPath"
     . $prosperoPath

    while($count -le 12) {
        try {
            $InstanceId = (Invoke-WebRequest -UseBasicParsing '169.254.169.254/latest/meta-data/instance-id').Content
            Write-Output "Successfully retrieve instance id: $InstanceId"
            break
        } catch {
            write-output "Unable to retrieve instance id from metadata..."
            start-sleep 5
            $count++
        }
    }

    # Rename instance by truncating AWS assigned instance id to 15 characters
    $ComputerName = if ($InstanceId.Length -eq 19) { "q" + $InstanceId.subString(5)} else { $InstanceId }


    If ($ComputerName) {
      Write-Output "Setting the machine name to $ComputerName"
      $AnswerFilePath = "C:\Windows\Panther\unattend.xml"
      $AnswerFile = [xml](Get-Content -Path $AnswerFilePath)
      $ns = New-Object System.Xml.XmlNamespaceManager($AnswerFile.NameTable)
      $ns.AddNamespace("ns", $AnswerFile.DocumentElement.NamespaceURI)
      $xmlComputerName = $AnswerFile.SelectSingleNode('/ns:unattend/ns:settings[@pass="specialize"]/ns:component[@name="Microsoft-Windows-Shell-Setup"]/ns:ComputerName', $ns)
      $xmlComputerName.InnerText = $ComputerName
      $AnswerFile.Save($AnswerFilePath)
    }
    If ($SsmPlatformSecretPath) {
      Write-Output "Reading the domain join user name and password from SSM parameter"
      $username = $(Read-SSMParameter $SsmPlatformSecretPath $InstanceId "bamboo_ad_join_user")
      $password = $(Read-SSMParameter $SsmPlatformSecretPath $InstanceId "bamboo_ad_join_password")

      if($username -and $password){
          Write-Output "Replacing the credentials in the answer file"
          (Get-Content $AnswerFilePath).replace('qcp-domain-user', $username ) | Set-Content $AnswerFilePath
          (Get-Content $AnswerFilePath).replace('qcp-domain-password', $password ) | Set-Content $AnswerFilePath
      }
    }
} catch {
    Write-Warning $_
}

Stop-Transcript