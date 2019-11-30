<# WinAuditPoShGUI | by Timothy Gruber

In progress.

https://timothygruber.com
https://github.com/tjgruber/WinAuditPoshGUI

#>

[cmdletbinding()]
    param(
        [Switch]$NoGUI #will be used in future
    )

    #region Update-Control is used for testing:
    Function Update-Control {
        Param (
            $Control,
            $Property,
            $Value,
            [switch]$AppendContent
        )
        If ($Property -eq "Close") {
            $syncHash.Window.Dispatcher.invoke([action]{$syncHash.Window.Close()},"Normal")
            Return
        }
        # This updates the control based on the parameters passed to the function
        $syncHash.$Control.Dispatcher.Invoke([action]{
            # This bit is only really meaningful for the TextBox control, which might be useful for logging progress steps
            If ($PSBoundParameters['AppendContent']) {
                $syncHash.$Control.AppendText($Value)
            } Else {
                $syncHash.$Control.$Property = $Value
            }
        }, "Normal")
    }
#endregion

#===========================================================================
#region Run script as elevated admin and unrestricted executionpolicy
#===========================================================================

    $myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    if ($myWindowsPrincipal.IsInRole($adminRole)) {
        $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)"
        $Host.UI.RawUI.BackgroundColor = "DarkBlue"
        Clear-Host
    } else {
        Start-Process PowerShell.exe -ArgumentList "-ExecutionPolicy Unrestricted -NoExit $($script:MyInvocation.MyCommand.Path)" -Verb RunAs
        Exit
    }
#endregion

Write-Host "Running WinAuditPoShGUI | by Timothy Gruber...`n`nClosing this window will close WinAuditPoShGUI.`n"

<###############
Main Window
###############>

$syncHash = [hashtable]::Synchronized(@{ })
$mainRunspace = [runspacefactory]::CreateRunspace()
$mainRunspace.Name = "MainWindow"
$mainRunspace.ApartmentState = "STA"
$mainRunspace.ThreadOptions = "ReuseThread"
$mainRunspace.Open()
$mainRunspace.SessionStateProxy.SetVariable("syncHash", $syncHash)
$psMainWindow = [PowerShell]::Create().AddScript({
    Add-Type -AssemblyName PresentationFramework

    <###############
    FUNCTIONS
    ###############>
    function Get-AuditPolicy {
        [CmdletBinding()]
        Param(
            [Parameter (Position=0)]
            [string]$Category,
            [Parameter (Position=1)]
            [string]$Policy,
            [Parameter (Position=2)]
            [string]$SecuritySetting
        )
        $auditPolicy = (auditpol /get /Category:*)
        $definedMatch = ($auditPolicy | Select-String $Policy) -replace "[ ]{2,}","" -replace "$Policy$Setting","$Policy $Setting"
    $template = @"
{Policy*:$Policy} {SecuritySetting:Success}
{Policy*:$Policy} {SecuritySetting:Failure}
{Policy*:$Policy} {SecuritySetting:Success and Failure}
{Policy*:$Policy} {SecuritySetting:No Auditing}
"@
    $definedMatch | ConvertFrom-String -TemplateContent $template
    }

    function Invoke-FileSystemSliderCheck {
        [cmdletbinding()]
        param()
        $policyData = Get-AuditPolicy -Policy "File System"
        switch ($policyData.SecuritySetting) {
            'No Auditing' {
                $syncHash.fileSystemSlider.Value = "0"
                $syncHash.fileSystemOffLabel.Foreground = "Red"
                $syncHash.fileSystemOnLabel.Foreground = "Black"
            }
            'Failure' {
                $syncHash.fileSystemSlider.Value = "0"
                $syncHash.fileSystemOffLabel.Foreground = "Red"
                $syncHash.fileSystemOnLabel.Foreground = "Black"
            }
            'Success' {
                $syncHash.fileSystemSlider.Value = "1"
                $syncHash.fileSystemOnLabel.Foreground = "Green"
                $syncHash.fileSystemOffLabel.Foreground = "Black"
            }
            'Success and Failure' {
                $syncHash.fileSystemSlider.Value = "1"
                $syncHash.fileSystemOnLabel.Foreground = "Green"
                $syncHash.fileSystemOffLabel.Foreground = "Black"
            }
            Default {}
        }
    }

    # Get-Folder function is from https://stackoverflow.com/a/57494414
    function Get-Folder($initialDirectory) {
        [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
        $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $FolderBrowserDialog.RootFolder = 'MyComputer'
        if ($initialDirectory) { $FolderBrowserDialog.SelectedPath = $initialDirectory }
        [void] $FolderBrowserDialog.ShowDialog()
        return $FolderBrowserDialog.SelectedPath
    }

    function Invoke-SelectedFolderAclCheck {
        [cmdletbinding()]
        param(
            [string]$selectedFolder
        )
        $syncHash.selectedFolder = $selectedFolder
        $syncHash.fileFolderAuditing = (Get-Acl $syncHash.selectedFolder -Audit).Audit
        if ($syncHash.fileFolderAuditing.FileSystemRights) {
            # Auditing information exists for the folder. Adjust GUI accordingly.
            $syncHash.fileSystemFolderGroupBox.Header = "Folder Auditing Details:"
            $syncHash.fileSystemNameListBox.Visibility = "Visible"
            $syncHash.fileSystemValueListBox.Visibility = "Visible"
            $syncHash.Window.Height = "450"
            $syncHash.fileSystemFolderInfoGrid.Height = "370"
            $syncHash.fileSystemFolderGroupBox.Height = "150"
            $syncHash.fileFolderAuditing = (Get-Acl $syncHash.selectedFolder -Audit).Audit
            foreach ($item in $syncHash.fileSystemNameListBox.Items.Name) {
                $syncHash.$item.Visibility = "Visible"
                $syncHash.$item.Padding = "0"
                $syncHash.$item.FontWeight = "Bold"
            }
            $syncHash.fileSystemListBoxLabelFILESYSTEMRIGHTS_value.Content = $syncHash.fileFolderAuditing.FileSystemRights
            $syncHash.fileSystemListBoxLabelAUDITFLAGS_value.Content = $syncHash.fileFolderAuditing.AuditFlags
            $syncHash.fileSystemListBoxLabelIDENTITYREFERENCE_value.Content = $syncHash.fileFolderAuditing.IdentityReference
            $syncHash.fileSystemListBoxLabelISINHERITED_value.Content = $syncHash.fileFolderAuditing.IsInherited
            foreach ($item in $syncHash.fileSystemValueListBox.Items.Name) {
                $syncHash.$item.Visibility = "Visible"
                $syncHash.$item.Padding = "0"
                if ($item -eq "fileSystemListBoxLabelFOLDERNAME_value") {
                    $syncHash.$item.ToolTip = $syncHash.selectedFolder
                }
                if ($item -eq "fileSystemListBoxLabelFILESYSTEMRIGHTS_value") {
                    $syncHash.$item.ToolTip = $syncHash.fileFolderAuditing.FileSystemRights
                }
            }
            $syncHash.fileSystemEnableFolderAuditingButton.Add_MouseEnter({
                $syncHash.StatusBarText.Text = "Further modify auditing for selected folder."
            })
            $syncHash.fileSystemEnableFolderAuditingButton.Visibility = "Visible"
            $syncHash.fileSystemEnableFolderAuditingButton.Content = "Modify"

        } else {
            $syncHash.fileSystemFolderGroupBox.Header = "Auditing is not enabled for selected folder."
            $syncHash.fileSystemNameListBox.Visibility = "Hidden"
            $syncHash.fileSystemValueListBox.Visibility = "Hidden"
            $syncHash.fileSystemEnableFolderAuditingButton.Content = "Enable"
            $syncHash.fileSystemEnableFolderAuditingButton.Add_MouseEnter({
                $syncHash.StatusBarText.Text = "Enable 'Full' rights auditing for everyone on selected folder."
            })
            $syncHash.fileSystemEnableFolderAuditingButton.Visibility = "Visible"
            $syncHash.Window.Height = "340"
            $syncHash.fileSystemFolderGroupBox.Height = "50"
        }#end if

    }#end Invoke-SelectedFolderAclCheck

    ########################
    #END FUNCTIONS
    ########################

    [xml]$xaml = @"
    <Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="WinAuditPoShGUI | by Timothy Gruber" ScrollViewer.VerticalScrollBarVisibility="Disabled" HorizontalAlignment="Left" VerticalAlignment="Top" Width="385" Height="325" ResizeMode="NoResize">
    <Grid>
        <DockPanel>
            <StatusBar DockPanel.Dock="Bottom" BorderThickness="2,2,2,2" Background="#FFF1EDED">
                <StatusBar.BorderBrush>
                    <LinearGradientBrush EndPoint="0.5,1" MappingMode="RelativeToBoundingBox" StartPoint="0.5,0">
                        <GradientStop Color="#FF494949" Offset="0"/>
                        <GradientStop Color="#FFBFBFBF" Offset="1"/>
                    </LinearGradientBrush>
                </StatusBar.BorderBrush>
                <StatusBarItem Margin="2,0,0,0">
                    <TextBlock Name="StatusBarText" Text="Ready..." />
                </StatusBarItem>
            </StatusBar>
            <TabControl Margin="0,0,0,0.4">
                <TabItem Header="File System" HorizontalAlignment="Left" VerticalAlignment="Top" TextOptions.TextFormattingMode="Display">
                    <Grid Name="fileSystemFolderInfoGrid" Margin="0" Height="245" HorizontalAlignment="Left" VerticalAlignment="Top">
                        <Label Content="Local File System Auditing is:" VerticalAlignment="Top" Height="30" FontSize="18" Padding="10,1" Margin="45,0,0,0" FontWeight="Bold" HorizontalAlignment="Left" Width="270"/>
                        <Slider Name="fileSystemSlider" Value="0" Width="80" Margin="135,43,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" Maximum="1" TickPlacement="BottomRight" IsSnapToTickEnabled="True" SmallChange="1"/>
                        <Label Name="fileSystemOffLabel" Content="OFF" HorizontalAlignment="Left" Margin="92,35,0,0" VerticalAlignment="Top" FontWeight="Bold" FontSize="16"/>
                        <Label Name="fileSystemOnLabel" Content="ON" HorizontalAlignment="Left" Margin="220,35,0,0" VerticalAlignment="Top" FontWeight="Bold" FontSize="16"/>
                        <Label Content="This is a global system setting and should be" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="33,72,0,0" Height="29" FontSize="14" Width="298" />
                        <Button Name="fileSystemSelectFolderButton" Content="Select Folder" Height="41" Margin="102,135,0,0" Width="150" FontSize="16" FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Top"/>
                        <Label Content="ON" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="41,90,0,0" FontWeight="Bold" FontSize="14" />
                        <Label Content=" to enable any file and folder auditing." VerticalAlignment="Top" HorizontalAlignment="Left" Margin="66,90,0,0" Height="33" FontSize="14" Width="259" />
                        <GroupBox Name="fileSystemFolderGroupBox" Header="No Folder Selected..." HorizontalAlignment="Left" Margin="10,187,0,0" VerticalAlignment="Top" Width="344" Height="30">
                            <DockPanel>
                                <Button Name="fileSystemEnableFolderAuditingButton" DockPanel.Dock="Bottom" Visibility="Hidden" Content="Enable" FontSize="14" FontWeight="Medium" VerticalAlignment="Top" Margin="0,5,0,0" Padding="10,1" />
                                <ListBox Name="fileSystemValueListBox" DockPanel.Dock="Right" MinWidth="212" MaxWidth="212" Visibility="Hidden" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Disabled">
                                    <Label Name="fileSystemListBoxLabelFOLDERNAME_value" Visibility="Hidden"/>
                                    <Label Name="fileSystemListBoxLabelFILESYSTEMRIGHTS_value" Visibility="Hidden"/>
                                    <Label Name="fileSystemListBoxLabelAUDITFLAGS_value" Visibility="Hidden"/>
                                    <Label Name="fileSystemListBoxLabelIDENTITYREFERENCE_value" Visibility="Hidden"/>
                                    <Label Name="fileSystemListBoxLabelISINHERITED_value" Visibility="Hidden"/>
                                </ListBox>
                                <ListBox Name="fileSystemNameListBox" DockPanel.Dock="Left" HorizontalAlignment="Left" MinWidth="120" MaxWidth="120" Visibility="Hidden" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Disabled">
                                    <Label Name="fileSystemListBoxLabelFOLDERNAME" Visibility="Hidden" Content="Folder Name:"/>
                                    <Label Name="fileSystemListBoxLabelFILESYSTEMRIGHTS" Visibility="Hidden" Content="Audit Rights:"/>
                                    <Label Name="fileSystemListBoxLabelAUDITFLAGS" Visibility="Hidden" Content="Audit Flags:"/>
                                    <Label Name="fileSystemListBoxLabelIDENTITYREFERENCE" Visibility="Hidden" Content="Audit Who?"/>
                                    <Label Name="fileSystemListBoxLabelISINHERITED" Visibility="Hidden" Content="Is Inherited?"/>
                                </ListBox>
                            </DockPanel>
                        </GroupBox>
                    </Grid>
                </TabItem>
            </TabControl>
        </DockPanel>
    </Grid>
</Window>
"@

    $xamlReader = (New-Object System.Xml.XmlNodeReader $xaml)
    $syncHash.Window = [Windows.Markup.XamlReader]::Load( $xamlReader )

    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") |
        ForEach-Object {
            $syncHash.($_.Name) = $syncHash.Window.FindName($_.Name)
        }

    $syncHash.fileSystemSlider.Add_MouseEnter({
        if ($syncHash.fileSystemSlider.Value -eq 0) {
            $syncHash.StatusBarText.Text = "Click to switch ON"
        } else {
            $syncHash.StatusBarText.Text = "Click to switch OFF"
        }
    })

    $syncHash.fileSystemSlider.Add_MouseLeave({
        if ($syncHash.selectedFolder) {
            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
        } else {
            $syncHash.StatusBarText.Text = "Ready..."
        }
    })

    $syncHash.fileSystemSlider.Add_ValueChanged({
        switch ($syncHash.fileSystemSlider.Value) {
            1 {
                $enableFileSystem = (auditpol /set /subcategory:"File System" /success:enable /failure:enable)
                Invoke-FileSystemSliderCheck
            }
            Default {
                $disableFileSystem = (auditpol /set /subcategory:"File System" /success:disable /failure:disable)
                Invoke-FileSystemSliderCheck
            }
        }
    })

    $syncHash.fileSystemSelectFolderButton.Add_MouseEnter({
        $syncHash.StatusBarText.Text = "Select folder to enable auditing"
    })

    $syncHash.fileSystemSelectFolderButton.Add_MouseLeave({
        if ($syncHash.selectedFolder) {
            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
        } else {
            $syncHash.StatusBarText.Text = "Ready..."
        }
    })

    $syncHash.fileSystemSelectFolderButton.Add_Click({
        $syncHash.selectedFolder = Get-Folder "$env:USERPROFILE"
        if ($syncHash.selectedFolder) {

            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
            $syncHash.fileSystemListBoxLabelFOLDERNAME_value.Content = $syncHash.selectedFolder

            Invoke-SelectedFolderAclCheck -selectedFolder $syncHash.selectedFolder
        }#end if

    })#end fileSystemSelectFolderButton.Add_Click

    $syncHash.fileSystemEnableFolderAuditingButton.Add_MouseLeave({
        if ($syncHash.selectedFolder) {
            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
        } else {
            $syncHash.StatusBarText.Text = "Ready..."
        }
    })

    $syncHash.fileSystemEnableFolderAuditingButton.Add_Click({
        if ($syncHash.fileSystemEnableFolderAuditingButton.Content -eq "Enable") {
            $IdentityReference = "Everyone"
            $FileSystemRights = "DeleteSubdirectoriesAndFiles, Modify, ChangePermissions, TakeOwnership"
            $InheritanceFlags = "ContainerInherit, ObjectInherit"
            $AuditFlags = "Success, Failure"
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAuditRule($IdentityReference,$FileSystemRights,$InheritanceFlags,"None",$AuditFlags)
            $selectedACL = Get-Acl -Path $syncHash.selectedFolder
            $selectedACL.SetAuditRule($AccessRule)
            $selectedACL | Set-Acl -Path $syncHash.selectedFolder
            Invoke-SelectedFolderAclCheck -selectedFolder $syncHash.selectedFolder
        }
    })

    Invoke-FileSystemSliderCheck
    [Void]$syncHash.Window.ShowDialog()
    $syncHash.Error = $Error
})

if (-not($NoGUI)) {
    $psMainWindow.Runspace = $mainRunspace
    $main = $psMainWindow.BeginInvoke()
}

########################
#END MAIN WINDOW
########################
<#

== To Do ==============================================================
    1. Add 'Remove' button under 'Modify' to remove folder auditing.
    2. Have the 'Modify' button open up selected folder properties.
=======================================================================

$psMainWindow.EndInvoke($main)
$mainRunspace.Close()

#>
