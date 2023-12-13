# -----------------------------------------------------------------------------
# Module provides QCP specific helper scripts for interacting with AWS services
# This module should be imported as part of global PowerShell profile to provide
# direct cmdlet access from users' bootstrap scripts.
# -----------------------------------------------------------------------------

# Obtain instance ID and REGION from metada

if (!$Global:INSTANCE_ID) {
  $webclient = New-Object System.Net.WebClient
  $Global:INSTANCE_ID = $webclient.DownloadString("http://169.254.169.254/latest/meta-data/instance-id")
}

if (!$Global:REGION) {
  $webclient = New-Object System.Net.WebClient
  $AZ=$webclient.DownloadString("http://169.254.169.254/latest/meta-data/placement/availability-zone")
  $Global:REGION = $AZ.Substring(0,$AZ.Length-1)
}


# -----------------------------------------------------------------------------
# Script: Attach-Volume
# comments: Script is used for attaching EC2 volume to running instance
# -----------------------------------------------------------------------------

function Attach-Volume {

  param(
    [parameter(Mandatory)][String]$Volume,
    [parameter(Mandatory)][String]$Device
  )

  $disks_before = Get-Disk; $volumes_before = Get-Volume

  # Run Attachment
  try {
    Add-EC2Volume -InstanceId $INSTANCE_ID -VolumeId $volume -Device $device
    Write-Verbose "INFO: Attached volume $volume to $INSTANCE_ID"
  } catch { Write-Warning "ERROR: Unable to attach $volume to $INSTANCE_ID as device $device"; throw }

  do {
    #EC2Config disk initialisation workaround
    $attached_volume = (Get-Volume).DriveLetter | ? {!($volumes_before.DriveLetter -contains $_)}
    $counter+=5; Start-Sleep 5
    #Restart-Service "EC2Config"
  } while (!$attached_volume -and $counter -lt 30)

  if ($attached_volume) {

    Write-Verbose "INFO: Volume $attached_volume already initialised on the attached volume"

  } else {

    # Format disk if not allocated
    $attached_disk = (Get-Disk).number | ? {!($disks_before.number -contains $_)}

    $Disk = Get-Disk $attached_disk

    if($Disk.IsOffline) {
      Set-Disk -Number $attached_disk -IsOffline $False
      Write-Verbose "Info: Set disk $attached_disk to Online"
    }

    if ($disk.IsReadonly) {
      Set-Disk -Number $attached_disk -IsReadonly $False
      Write-Verbose "Info: Set disk $attached_disk to ReadWrite"
    }

    if($Disk.Numberofpartitions -eq 0) {

      try {
        Initialize-Disk $attached_disk
        Write-verbose "Info: Disk $attached_disk is initialized"
        New-Partition -DiskNumber $attached_disk -UseMaximumSize -AssignDriveLetter | Format-Volume -Force -Confirm:$false
        Start-Sleep 5

      } catch { throw "Unable to initialise and format new volume" }
    }
  }
}

# -----------------------------------------------------------------------------
# Script: Detach-Volume
# comments: Script is used for detaching EC2 volume from running instance
# -----------------------------------------------------------------------------

function Detach-Volume {

  param(
      [parameter(Mandatory)][String]$Volume
  )

  try {

    Dismount-EC2Volume -VolumeId $volume; $count = 0

    do { $volume_state = (Get-EC2Volume -VolumeId $volume).state; Start-Sleep 1 }
    while ($volume_state -ne "available" -and $count -lt 120)

    if($volume_state -ne "available" -and $count -ge 180) { throw "WARNING: Was unable to detach volume" }
    else { Write-Output "INFO: Instance $volume successfully detached"; return $true }

  } catch { throw "WARNING: Was unabled to dismount $volume" }

}

# -----------------------------------------------------------------------------
# Script: Attach-Eni
# comments: Script is used for attaching EC2 eni to running instance
# -----------------------------------------------------------------------------

function Attach-Eni {

  param(
    [parameter(Mandatory)][String]$Eni,
    [parameter(Mandatory=$false)][int]$Device = 1
  )

  try {

    Add-EC2NetworkInterface -InstanceId $INSTANCE_ID -NetworkInterfaceId $Eni -DeviceIndex $Device
    Write-Output "eni $Eni was attached successfully to $INSTANCE_ID"

  } catch {

    Write-Warning "Error during attachment of eni $Eni to $INSTANCE_ID"
  }

}

# -----------------------------------------------------------------------------
# Script: Detach-eni
# comments: Script is used for detaching EC2 eni from running instance
# -----------------------------------------------------------------------------

function Detach-Eni {
  param(
      [parameter(Mandatory)][String]$Eni
  )

  try {

    Dismount-EC2NetworkInterface -AttachmentId (Get-EC2NetworkInterface $Eni).Attachment.AttachmentId -Force
    Write-Output "NetworkInterface $Eni was detached successfully"

  } catch {

    Write-Warning "Error during detachment of eni $Eni"
  }
}

# Private function - converts Base64 Input to System.IO.MemoryStream
function ConvertFrom-Base64toMemoryStream{
  param(
    [parameter(Mandatory)][string]$Base64Input
  )

  [byte[]]$bytearray = [System.Convert]::FromBase64String($Base64Input)
  $stream = New-Object System.IO.MemoryStream($bytearray,0,$bytearray.Length)
  return $stream
}

# Private function - converts a Stream to a String Output
function ConvertFrom-StreamToString{
  param(
    [parameter(Mandatory)]
    [System.IO.MemoryStream]$inputStream
  )
  $reader = New-Object System.IO.StreamReader($inputStream);
  $inputStream.Position = 0;
  return $reader.ReadToEnd()
}

# -----------------------------------------------------------------------------
# Script: KMS-Decrypt
# comments: Script for decrypting Base64 input to a plaintext string output
# -----------------------------------------------------------------------------

function KMS-Decrypt {

  param(
      [parameter(Mandatory)]
      [String]$Base64Input
  )

  try {

    # Decrypt the secret from the file
    $DecryptedOutputStream = Invoke-KMSDecrypt -CiphertextBlob $(ConvertFrom-Base64toMemoryStream -Base64Input $Base64Input) -region $REGION

    # Convert the decrypted stream to a strimg
    return(ConvertFrom-StreamToString -inputStream $DecryptedOutputStream.Plaintext)

  } catch {

    Write-Warning "Unable to use KMS for decryption"

  }
}
# Private function - converts a string to a memory stream
function ConvertFrom-StringToMemoryStream{

  param(
    [parameter(Mandatory)][string]$InputString
  )

  $stream = New-Object System.IO.MemoryStream;
  $writer = New-Object System.IO.StreamWriter($stream);
  $writer.Write($InputString);
  $writer.Flush();
  return $stream
}


# Private function - converts bytestream to Base64
function ConvertFrom-StreamToBase64{

  param(
    [parameter(Mandatory)][System.IO.MemoryStream]$inputStream
  )

  $reader = New-Object System.IO.StreamReader($inputStream);
  $inputStream.Position = 0;
  return  [System.Convert]::ToBase64String($inputStream.ToArray())
}

# -----------------------------------------------------------------------------
# Script: KMS-Encrypt
# comments: Script for encryption plaintext string with KMS
# -----------------------------------------------------------------------------

function KMS-Encrypt {

  param(
    [parameter(Mandatory)][String]$Plaintext,
    [parameter(Mandatory=$false)][String]$Key = $pipeline_KmsKeyArn
  )

  try {
    $EncryptedOuput = (Invoke-KMSEncrypt -KeyId $Key -Plaintext $(ConvertFrom-StringToMemoryStream $Plaintext) -region $REGION)
    return (ConvertFrom-StreamToBase64 -inputStream $EncryptedOuput.CiphertextBlob)

  } catch {
    Write-Warning "Unable to use KMS for encryption using $Key"
  }
}

# -----------------------------------------------------------------------------
# Script: KMS-EncryptFile
# comments: Script for encrypting a specified file to encrypted string output
# -----------------------------------------------------------------------------

function KMS-EncryptFile {
  param(
    [parameter(Mandatory = $false)][String]$Key = $pipeline_KmsKeyArn,
    [parameter(Mandatory)][String]$File
  )

  try {
    Kms-Encrypt -Key $Key -Plaintext (Get-Content $File)
  } catch {
    Write-Warning "Unable to use $Key to encrypt $File"
  }
}

# -----------------------------------------------------------------------------
# Script: Receive-LifecycleHookMessage
# comments: Script polls nominates SQS queue for a message matching instance id
# -----------------------------------------------------------------------------
function Receive-LifecycleHookMessage {
  param(
    [parameter(Mandatory = $true)][String]$SqsQueueEndpoint,
    [int]$WaitTimeInSeconds = 20,
    [String]$InstanceIdMatch = $INSTANCE_ID,
    [String]$LifecycleTransitionMatch = ""
  )

  # Receive Lifecycle Hook messages
  # Note: VisibilityTimeout is set to 0 so other instances can also receive these messages
  $messages = Receive-SQSMessage -QueueUrl $SqsQueueEndpoint -VisibilityTimeout 0 -WaitTimeInSeconds $WaitTimeInSeconds -MessageCount 10

  # Look to see if any messages meet our criteria
  foreach ($message in $messages) {
    $messageBody = ConvertFrom-Json $message.Body
    if ($messageBody.EC2InstanceId -NotMatch $InstanceIdMatch) {
      echo "Instance id does not match - skipping"
      # InstanceId match failed - message doesn't match
      continue
    }

    if ($messageBody.LifecycleTransition -NotMatch $LifecycleTransitionMatch) {
      # Lifecycle transition match failed - message doesn't match
      continue
    }

    # All matches passed - return the message
    return $message
  }

  return $null
}

# -----------------------------------------------------------------------------
# Script: Complete-LifecycleHookMessage
# comments: Script removes removes message from SQS and completes a lifecycle hook
# -----------------------------------------------------------------------------

function Complete-LifecycleHookMessage {
  param(
    [parameter(Mandatory = $true)][String]$SqsQueueEndpoint,
    [parameter(Mandatory = $true)]$Message,
    [parameter(Mandatory = $false)][String]$Result = "CONTINUE"
  )

  # Decode message body
  $messageBody = ConvertFrom-Json $message.Body

  # Remove the message from the SQS Queue - it has been handled
  Remove-SQSMessage -QueueUrl $SqsQueueEndpoint -ReceiptHandle $Message.ReceiptHandle -Force

  # Complete the lifecycle hook
  Complete-ASLifecycleAction -LifecycleHookName $MessageBody.LifecycleHookName -AutoScalingGroupName $MessageBody.AutoScalingGroupName -LifecycleActionResult $Result -LifecycleActionToken $MessageBody.LifecycleActionToken
}

# -----------------------------------------------------------------------------
# Script: Clean-LifecycleHookTestNotifications
# comments: Script removes autoscaling test messages from SQS queue
# -----------------------------------------------------------------------------

function Clean-LifecycleHookTestNotifications {
  param(
    [parameter(Mandatory = $true)]
    [String]$SqsQueueEndpoint
  )

  $cleaned = $true
  while ($cleaned) {
    $messages = Receive-SQSMessage -QueueUrl $SqsQueueEndpoint -VisibilityTimeout 10 -WaitTimeInSeconds 5 -MessageCount 10

    # Look to see if any messages meet our criteria
    $cleaned = $false
    foreach ($message in $messages) {
      $messageBody = ConvertFrom-Json $message.Body
      if ($messageBody.Event -eq "autoscaling:TEST_NOTIFICATION") {
        Write-Output "Removing autoscaling:TEST_NOTIFICATION message $($message.MessageId)"
        Remove-SQSMessage -QueueUrl $SqsQueueEndpoint -ReceiptHandle $message.ReceiptHandle -Force
        $cleaned = $true
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Script: Put-CustomMetric
# comments: Script sends a custom metric specified as MetricName
# -----------------------------------------------------------------------------

function Put-CustomMetric {
  param(
    [parameter(Mandatory = $true)][String]$MetricName,
    [parameter(Mandatory = $true)]$Value,
    [parameter(Mandatory = $false)][String]$Unit = "Count"
  )

    $Tags = @{
        AMS = $pipeline_Ams
        QDA=$pipeline_Qda
        AS=$pipeline_As
        ASE=$pipeline_Ase
        BRANCH=$pipeline_Branch
        BUILD=$pipeline_Build
        COMPONENT=$pipeline_Component
    }


    $Dimensions = @()
    foreach ($key in $Tags.Keys) {
        $Dimension = New-Object Amazon.CloudWatch.Model.Dimension
        $Dimension.Name = $key
        $Dimension.Value = $Tags[$key]
        $Dimensions += $Dimension
    }

    $Data = New-Object Amazon.CloudWatch.Model.MetricDatum
    $Data.Timestamp = [DateTime]::UtcNow
    $Data.MetricName = $MetricName
    $Data.Value = $Value
    $Data.Unit = $Unit
    $Data.Dimensions = $Dimensions

    try {
        Write-CWMetricData -Namespace "QCP/Custom" -MetricData $Data
    } catch {
        Write-Warning "Unable to post custom metric with $Data"
    }
}

# -----------------------------------------------------------------------------
# Script: Configure-S3Versioning
# This script will help you enable and suspend versioning on your S3 buckets
# within the QCP environment quickly from your EC2 instances.
# This requires the AWS Powershell commandlets to function & suitable S3 permissions from IAM

# Usage: S3Versioning-Configure -Action { enable | suspend | status } -Bucketname [ bucketname ]
# -----------------------------------------------------------------------------

function Configure-S3Versioning {
  param (
    [Parameter()][string]$Action,
    [Parameter()][string]$Bucketname = $pipeline_AppBucketName
  )

  $commandname = $myInvocation.MyCommand.Name

  switch ($Action)
  {
    enable {
      Write-Host "Enabling versioning on bucket: $bucketname"
      Write-S3BucketVersioning -BucketName $bucketname -VersioningConfig_Status enabled -region $REGION
    }

    suspend {
      Write-Host "Suspending versioning on bucket: $bucketname"
      Write-S3BucketVersioning -BucketName $bucketname -VersioningConfig_Status suspended -region $REGION
    }

    status {
      Write-Host "The Status of  versioning on bucket: $bucketname is:"
      Get-S3BucketVersioning -BucketName $bucketname -region $REGION
    }

    default {
      Write-Host "Usage: $commandname -action { enable | suspend | status } -bucketname [ bucketname ]"
    }
  }
}


Export-ModuleMember -Function Attach-Volume,
                              Detach-Volume,
                              Attach-Eni,
                              Detach-Eni,
                              KMS-Encrypt,
                              KMS-EncryptFile,
                              KMS-Decrypt,
                              Receive-LifecycleHookMessage,
                              Complete-LifecycleHookMessage,
                              Clean-LifecycleHookTestNotifications,
                              Put-CustomMetric,
                              Configure-S3Versioning
