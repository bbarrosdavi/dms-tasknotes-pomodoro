import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "tasknotesPomodoro"

    StringSetting {
        settingKey: "vaultPath"
        label: "Caminho do Vault"
        description: "Diretório do Vault do Obsidian onde o TaskNotes está instalado (opcional se a ponte estiver ativa)"
        placeholder: "~/Documents/Obsidian/Vault"
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "autoFocusObsidian"
        label: "Focar Obsidian ao trocar tarefa"
        description: "Traz a janela do Obsidian para primeiro plano no Niri ao trocar ou abrir tarefas"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showTaskTitleOnBar"
        label: "Exibir título da tarefa na barra"
        description: "Mostra o nome da tarefa ao lado do tempo restante na DankBar"
        defaultValue: true
    }
}
