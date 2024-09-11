@REM hot key
powershell -Command Copy-Item .\keybindings.json $HOME\AppData\Roaming\Code\User\
 
@REM  copy ./keybindings.json $HOME/AppData/Roaming/Code/User/

powershell -Command Copy-Item .\settings.json $HOME\AppData\Roaming\Code\User\

@REM шаблоны для проектов по умолчанию
powershell -Command Copy-Item .\ProjectTemplates ~\AppData\Roaming\Code\User -force -recurse

@REM snippets
powershell -Command Copy-Item .\snippets ~\AppData\Roaming\Code\User -force -recurse