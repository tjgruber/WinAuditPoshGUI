<# WinAuditPoShGUI | by Timothy Gruber

Windows Auditing PowerShell GUI
    Version: 2019.12.03.03

Designed and written by Timothy Gruber:
    https://timothygruber.com
    https://github.com/tjgruber/WinAuditPoshGUI

#>

#region Run script as elevated admin and unrestricted executionpolicy
    $myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    if ($myWindowsPrincipal.IsInRole($adminRole)) {
        $Host.UI.RawUI.WindowTitle = "WinAuditPoShGUI | by Timothy Gruber"
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
    }#end Get-AuditPolicy

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
    }#end Invoke-FileSystemSliderCheck

    # Get-Folder function is from https://stackoverflow.com/a/57494414
    function Get-Folder($initialDirectory) {
        [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
        $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $FolderBrowserDialog.RootFolder = 'MyComputer'
        if ($initialDirectory) { $FolderBrowserDialog.SelectedPath = $initialDirectory }
        [void] $FolderBrowserDialog.ShowDialog()
        return $FolderBrowserDialog.SelectedPath
    }

    function Invoke-FileSystemAuditDataTable {
        [cmdletbinding()]
        param()
        $columns = @(
            'Keys'
            'Values'
        )
        $syncHash.dataTable = New-Object System.Data.DataTable
        [void]$syncHash.dataTable.Columns.AddRange($columns)
        foreach ($aclAuditProperty in $syncHash.fileFolderAuditing) {
            $aclAuditObjects = [PSCustomObject]@(
                @{'Folder Name:' = $syncHash.selectedFolder}
                @{'Audit Rights:' = $aclAuditProperty.FileSystemRights}
                @{'Audit Flags:' = $aclAuditProperty.AuditFlags}
                @{'Audit Who?' = $aclAuditProperty.IdentityReference.Value}
                @{'Is Inherited?' = [string]$aclAuditProperty.IsInherited}
            )
            foreach ($aclAuditObject in $aclAuditObjects) {
                $dataTableRow = @()
                foreach ($column in $columns) {
                    $dataTableRow += $aclAuditObject.$column
                }
                [void]$syncHash.dataTable.Rows.Add($dataTableRow)
            }
        }
        $syncHash.fileSystemDataGrid.ItemsSource = $syncHash.dataTable.DefaultView
        $syncHash.fileSystemDataGrid.GridLinesVisibility = "None"
        $syncHash.fileSystemDataGrid.IsReadOnly = $True
        $syncHash.fileSystemDataGrid.CanUserAddRows = $False
        ($syncHash.dataTable.Rows | Where-Object {$_.Keys -eq "Is Inherited?" -and $_.Values -eq $True}).Foreground = "Red"
    }#end Invoke-FileSystemAuditDataTable

    function Invoke-SelectedFolderAclCheck {
        [cmdletbinding()]
        param(
            [string]$selectedFolder
        )
        $syncHash.selectedFolder = $selectedFolder
        $syncHash.fileFolderAuditing = (Get-Acl $syncHash.selectedFolder -Audit).Audit
        if ($syncHash.fileFolderAuditing.FileSystemRights) {
            Invoke-FileSystemAuditDataTable
            $syncHash.fileSystemFolderGroupBox.Header = "Folder Auditing Details:"
            $syncHash.fileSystemDataGrid.Visibility = "Visible"
            if ($syncHash.fileFolderAuditing.Count -gt 1) {
                $syncHash.Window.Height = "530"
                $syncHash.fileSystemFolderInfoGrid.Height = "435"
                $syncHash.fileSystemFolderGroupBox.Height = "240"
            } else {
                $syncHash.Window.Height = "450"
                $syncHash.fileSystemFolderInfoGrid.Height = "355"
                $syncHash.fileSystemFolderGroupBox.Height = "155"
            }
            $syncHash.fileSystemModifyFolderAuditingButton.Add_MouseEnter({
                $syncHash.StatusBarText.Text = "Further modify auditing for selected folder."
            })
            $syncHash.fileSystemRemoveFolderAuditingButton.Add_MouseEnter({
                $syncHash.StatusBarText.Text = "Remove all auditing for selected folder."
            })
            $syncHash.fileSystemEnableFolderAuditingButton.Visibility = "Hidden"
            $syncHash.fileSystemEnableFolderAuditingButton.Width = "0"
            $syncHash.fileSystemModifyFolderAuditingButton.Visibility = "Visible"
            $syncHash.fileSystemRemoveFolderAuditingButton.Visibility = "Visible"
        } else {
            $syncHash.fileSystemFolderGroupBox.Header = "Auditing is not enabled for selected folder."
            $syncHash.fileSystemDataGrid.Visibility = "Hidden"
            $syncHash.fileSystemEnableFolderAuditingButton.Content = "Enable"
            $syncHash.fileSystemEnableFolderAuditingButton.Add_MouseEnter({
                $syncHash.StatusBarText.Text = "Enable 'Full' rights auditing for everyone on selected folder."
            })
            $syncHash.fileSystemRemoveFolderAuditingButton.Visibility = "Hidden"
            $syncHash.fileSystemEnableFolderAuditingButton.Width = "332"
            $syncHash.fileSystemEnableFolderAuditingButton.Visibility = "Visible"
            $syncHash.Window.Height = "340"
            $syncHash.fileSystemFolderGroupBox.Height = "50"
        }

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
                                <DockPanel DockPanel.Dock="Bottom" Margin="0,5,0,0">
                                    <Button Name="fileSystemEnableFolderAuditingButton" DockPanel.Dock="Right" Visibility="Hidden" Content="Enable" FontSize="14" FontWeight="Medium" VerticalAlignment="Top" Padding="10,1" Width="164" HorizontalAlignment="Right" />
                                    <Button Name="fileSystemModifyFolderAuditingButton" DockPanel.Dock="Right" Visibility="Hidden" Content="Modify" FontSize="14" FontWeight="Medium" VerticalAlignment="Top" Padding="10,1" Width="164" HorizontalAlignment="Right" />
                                    <Button Name="fileSystemRemoveFolderAuditingButton" DockPanel.Dock="Left" Visibility="Hidden" Content="Remove" FontSize="14" FontWeight="Medium" VerticalAlignment="Top" Padding="10,1" Width="164" HorizontalAlignment="Left" />
                                </DockPanel>
                                <DataGrid DockPanel.Dock="Top" Name="fileSystemDataGrid" HorizontalScrollBarVisibility="Visible" SelectionMode="Single" HeadersVisibility="None" Visibility="Hidden">
                                    <DataGrid.RowStyle>
                                        <Style TargetType="DataGridRow">
                                            <Style.Triggers>
                                                <DataTrigger Binding="{Binding Values}" Value="True">
                                                    <Setter Property="Foreground" Value="Red" />
                                                    <Setter Property="FontWeight" Value="Medium" />
                                                </DataTrigger>
                                                <DataTrigger Binding="{Binding Keys}" Value="Folder Name:">
                                                    <Setter Property="Background" Value="#F3F3F3" />
                                                    <Setter Property="FontWeight" Value="Medium" />
                                                </DataTrigger>
                                            </Style.Triggers>
                                        </Style>
                                    </DataGrid.RowStyle>
                                </DataGrid>
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
                [void](auditpol /set /subcategory:"File System" /success:enable /failure:enable)
                Invoke-FileSystemSliderCheck
            }
            Default {
                [void](auditpol /set /subcategory:"File System" /success:disable /failure:disable)
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
        }
    })#end fileSystemSelectFolderButton.Add_Click

    $syncHash.fileSystemEnableFolderAuditingButton.Add_MouseLeave({
        if ($syncHash.selectedFolder) {
            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
        } else {
            $syncHash.StatusBarText.Text = "Ready..."
        }
    })

    $syncHash.fileSystemModifyFolderAuditingButton.Add_MouseLeave({
        if ($syncHash.selectedFolder) {
            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
        } else {
            $syncHash.StatusBarText.Text = "Ready..."
        }
    })

    $syncHash.fileSystemRemoveFolderAuditingButton.Add_MouseLeave({
        if ($syncHash.selectedFolder) {
            $syncHash.StatusBarText.Text = "Selected folder: $($syncHash.selectedFolder)"
        } else {
            $syncHash.StatusBarText.Text = "Ready..."
        }
    })

    $syncHash.fileSystemEnableFolderAuditingButton.Add_Click({
        if ($syncHash.fileSystemEnableFolderAuditingButton.Content -eq "Enable") {
            $fileSystemRights = "DeleteSubdirectoriesAndFiles, Modify, ChangePermissions, TakeOwnership"
            $auditFlags = "Success, Failure"
            $identityReference = "Everyone"
            $inheritanceFlags = "ContainerInherit, ObjectInherit"
            $PropagationFlags = "None"
            $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule($identityReference,$fileSystemRights,$inheritanceFlags,$PropagationFlags,$auditFlags)
            $selectedACL = Get-Acl -Path $syncHash.selectedFolder
            $selectedACL.SetAuditRule($auditRule)
            $selectedACL | Set-Acl -Path $syncHash.selectedFolder
            Invoke-SelectedFolderAclCheck -selectedFolder $syncHash.selectedFolder
        }
    })

    $syncHash.fileSystemRemoveFolderAuditingButton.Add_Click({
        if ($syncHash.fileSystemRemoveFolderAuditingButton.Content -eq "Remove") {
            $selectedACLAudit = Get-Acl -Path $syncHash.selectedFolder -Audit
            $fileSystemRights = $selectedACLAudit.Audit.FileSystemRights
            $auditFlags = $selectedACLAudit.Audit.AuditFlags
            $identityReference = $selectedACLAudit.Audit.IdentityReference
            $inheritanceFlags = $selectedACLAudit.Audit.InheritanceFlags
            $PropagationFlags = $selectedACLAudit.Audit.PropagationFlags
            $auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule($identityReference,$fileSystemRights,$inheritanceFlags,$PropagationFlags,$auditFlags)
            $selectedACL = Get-Acl -Path $syncHash.selectedFolder
            $selectedACL.RemoveAuditRule($auditRule)
            $selectedACL | Set-Acl -Path $syncHash.selectedFolder
            Invoke-SelectedFolderAclCheck -selectedFolder $syncHash.selectedFolder
        }
    })

    $syncHash.fileSystemModifyFolderAuditingButton.Add_Click({
        if ($syncHash.fileSystemModifyFolderAuditingButton.Content -eq "Modify") {
            $shellobj = New-Object -com Shell.Application
            $folder = $shellobj.NameSpace("$($syncHash.selectedFolder)")
            $folder.Self.InvokeVerb("Properties")
            Invoke-SelectedFolderAclCheck -selectedFolder $syncHash.selectedFolder
        }
    })

    Invoke-FileSystemSliderCheck
    [Void]$syncHash.Window.ShowDialog()
    $syncHash.Error = $Error
})

$psMainWindow.Runspace = $mainRunspace
[void]$psMainWindow.BeginInvoke()

########################
#END MAIN WINDOW
########################
