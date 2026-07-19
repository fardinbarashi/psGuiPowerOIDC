function Update-UI {
    # Force UI render to keep the interface responsive
    $window.Dispatcher.Invoke([Action]{}, "Render")
}
