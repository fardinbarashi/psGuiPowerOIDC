function Show-ManualCodeInputDialog {
    param(
        [string]$AuthorizationUrl,
        [System.Windows.Window]$OwnerWindow = $null
    )

    [xml]$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Manual OIDC Authorization"
        Width="940"
        Height="760"
        MinWidth="900"
        MinHeight="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        Background="#181818"
        Foreground="#F5F5F5"
        FontFamily="Segoe UI"
        FontSize="12">

    <Window.Resources>
        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>

        <Style x:Key="MutedText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#B0BEC5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>

        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#2A2A2A"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#3A3A3A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#1F1F1F"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#424242"/>
                                <Setter Property="Foreground" Value="#9E9E9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#0D47A1"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#1565C0"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#0B3D91"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#1B5E20"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2E7D32"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#174D1B"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#B71C1C"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#C62828"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#8E1616"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#232323"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ScrollViewer x:Name="PART_ContentHost"
                                          Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#42A5F5"/>
                            </Trigger>
                            <Trigger Property="IsReadOnly" Value="True">
                                <Setter Property="Foreground" Value="#CFD8DC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="20"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#202020" CornerRadius="14" Padding="20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="16"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Width="46" Height="46" CornerRadius="12" Background="#0D47A1">
                    <TextBlock Text="OIDC" Foreground="White" FontWeight="Bold" FontSize="11"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>

                <StackPanel Grid.Column="2">
                    <TextBlock Text="Manual Authorization Code"
                               FontSize="22"
                               FontWeight="Bold"
                               Foreground="White"/>
                    <TextBlock Margin="0,8,0,0"
                               Style="{StaticResource MutedText}"
                               Text="Log in through the browser. Then paste the final redirected URL, or only the authorization code, in the input field below."/>
                </StackPanel>
            </Grid>
        </Border>

        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel>
                <Border Background="#1F1F1F" CornerRadius="12" Padding="16" Margin="0,0,0,16">
                    <StackPanel>
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Steps"/>
                        <TextBlock Style="{StaticResource MutedText}" Text="1. Click Open Browser."/>
                        <TextBlock Style="{StaticResource MutedText}" Text="2. Sign in to your OIDC provider."/>
                        <TextBlock Style="{StaticResource MutedText}" Text="3. After login, copy the final redirect URL from the browser address bar."/>
                        <TextBlock Style="{StaticResource MutedText}" Text="4. Paste the final redirect URL below and click OK."/>
                    </StackPanel>
                </Border>

                <TextBlock Style="{StaticResource SectionTitle}" Text="Authorization URL"/>
                <TextBox x:Name="AuthUrlBox"
                         Style="{StaticResource ModernTextBox}"
                         Height="84"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Margin="0,0,0,12"/>

                <StackPanel Orientation="Horizontal" Margin="0,0,0,18">
                    <Button x:Name="CopyUrlButton"
                            Content="Copy Auth URL"
                            Style="{StaticResource ModernButton}"
                            Width="150"
                            Height="40"/>

                    <Button x:Name="OpenBrowserButton"
                            Content="Open Browser"
                            Style="{StaticResource PrimaryButton}"
                            Width="150"
                            Height="40"/>

                    <Button x:Name="PasteClipboardButton"
                            Content="Paste Clipboard"
                            Style="{StaticResource ModernButton}"
                            Width="150"
                            Height="40"/>
                </StackPanel>

                <TextBlock Style="{StaticResource SectionTitle}" Text="Paste final redirect URL or authorization code here"/>
                <TextBox x:Name="InputBox"
                         Style="{StaticResource ModernTextBox}"
                         Height="145"
                         AcceptsReturn="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Margin="0,0,0,14"/>

                <Border Background="#1D2A36" CornerRadius="10" Padding="14" Margin="0,0,0,10">
                    <TextBlock Style="{StaticResource MutedText}"
                               Foreground="#90CAF9"
                               Text="Tip: Do not paste the Authorization URL from the top field. Paste the final URL after login, for example http://localhost:44300/signin-oidc?code=...&amp;state=..."/>
                </Border>

                <Border x:Name="ValidationBorder" Background="#3A1F1F" CornerRadius="10" Padding="14" Visibility="Collapsed">
                    <TextBlock x:Name="ValidationText"
                               Foreground="#FFCDD2"
                               TextWrapping="Wrap"/>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="CancelButton"
                    Grid.Column="1"
                    Content="Cancel"
                    Style="{StaticResource DangerButton}"
                    Width="110"
                    Height="42"/>

            <Button x:Name="OkButton"
                    Grid.Column="3"
                    Content="OK"
                    Style="{StaticResource SuccessButton}"
                    Width="110"
                    Height="42"/>
        </Grid>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $dialogXaml
    $dialog = [Windows.Markup.XamlReader]::Load($reader)

    if ($OwnerWindow) {
        $dialog.Owner = $OwnerWindow
        $dialog.WindowStartupLocation = "CenterOwner"
    }

    $AuthUrlBox           = $dialog.FindName("AuthUrlBox")
    $InputBox             = $dialog.FindName("InputBox")
    $CopyUrlButton        = $dialog.FindName("CopyUrlButton")
    $OpenBrowserButton    = $dialog.FindName("OpenBrowserButton")
    $PasteClipboardButton = $dialog.FindName("PasteClipboardButton")
    $OkButton             = $dialog.FindName("OkButton")
    $CancelButton         = $dialog.FindName("CancelButton")
    $ValidationBorder     = $dialog.FindName("ValidationBorder")
    $ValidationText       = $dialog.FindName("ValidationText")

    $AuthUrlBox.Text = $AuthorizationUrl
    $dialog.Tag = $null

    function Set-ManualDialogValidationMessage {
        param([string]$Message)
        $ValidationText.Text = $Message
        $ValidationBorder.Visibility = "Visible"
    }

    $CopyUrlButton.Add_Click({
        [System.Windows.Clipboard]::SetText($AuthorizationUrl)
    })

    $OpenBrowserButton.Add_Click({
        Start-Process $AuthorizationUrl
    })

    $PasteClipboardButton.Add_Click({
        if ([System.Windows.Clipboard]::ContainsText()) {
            $InputBox.Text = [System.Windows.Clipboard]::GetText()
            $InputBox.CaretIndex = $InputBox.Text.Length
            $InputBox.Focus() | Out-Null
            $ValidationBorder.Visibility = "Collapsed"
        }
    })

    $OkButton.Add_Click({
        $inputValue = $InputBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            Set-ManualDialogValidationMessage "Paste the final redirected URL or the authorization code before clicking OK."
            return
        }

        if ($inputValue -eq $AuthorizationUrl -or ($inputValue -match "response_type=code" -and $inputValue -notmatch "[?&]code=")) {
            Set-ManualDialogValidationMessage "This looks like the Authorization URL, not the final redirect URL. First complete login in the browser. Then copy the final URL from the browser address bar. It must contain code=..."
            return
        }

        $dialog.Tag = $inputValue
        $dialog.DialogResult = $true
        $dialog.Close()
    })

    $CancelButton.Add_Click({
        $dialog.DialogResult = $false
        $dialog.Close()
    })

    $dialog.Add_ContentRendered({
        $InputBox.Focus() | Out-Null
    })

    $result = $dialog.ShowDialog()

    if (-not $result) {
        throw "Manual login was cancelled"
    }

    return [string]$dialog.Tag
}
