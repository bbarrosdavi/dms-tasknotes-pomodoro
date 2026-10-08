# DMS TaskNotes Pomodoro

Integração nativa de Pomodoro e gerenciamento de tarefas entre o **Obsidian TaskNotes** e o **Dank Material Shell (DMS)** no compositor Wayland **Niri**.

Oferece uma janela flutuante com fundo translúcido e efeito fosco (GPU blur), redimensionável por arraste das bordas com escala responsiva, e um pill na DankBar para controle rápido e colapso visual.

---

## Recursos

- **Janela Flutuante Fosca & Responsiva**:
  - Bordas interativas para redimensionamento livre em qualquer direção (8 zonas de resize nativas do Wayland).
  - Escala dinâmica contínua (`scaleFactor`): tipografia, ícones, botões e barras de progresso se adaptam suavemente ao tamanho da janela.
  - Efeito de vidro fosco com cantos arredondados, herdando as cores ativas do tema do DMS (Material You / Matugen) e blur do Niri.
- **Integração Bidirecional com o Obsidian**:
  - **Tarefa em execução**: exibe o nome da nota e status da sessão atual. Clicar no card foca instantaneamente o Obsidian e abre a nota correspondente.
  - **Trocar Tarefa**: botão dedicado que invoca o modal do seletor de tarefas do TaskNotes no Obsidian e traz a janela para primeiro plano.
  - **Controle sem roubo de foco**: botões de *Play/Pause*, *Stop* e *Pular Pausa* utilizam barramento local via IPC (`tmpfs`), permitindo pausar e retomar o timer sem que o compositor troque o foco do seu terminal ou navegador.
- **Pill na DankBar**:
  - Exibe ícone de estado (foco ou pausa), cronômetro em tempo real (MM:SS) e nome da tarefa ativa.
  - **Clique esquerdo**: alterna/colapsa a janela flutuante.
  - **Clique direito**: pausa ou retoma o timer instantaneamente.
- **Controle por IPC & Atalhos**:
  - Exposição de métodos via `dms ipc call tasknotesPomodoro <ação>` para integração com atalhos de teclado do Niri.

---

## Arquitetura

```text
┌─────────────────────────┐               ┌─────────────────────────┐
│     Obsidian App        │               │   Dank Material Shell   │
│  (TaskNotes + Bridge)   │               │       (Quickshell)      │
└────────────┬────────────┘               └────────────┬────────────┘
             │                                         │
             ├────── Estado do Pomodoro (JSON) ───────►│  [DankBar Pill]
             │      /run/user/$UID/tasknotes-pomodoro.json │
             │                                         │
             │◄───── Comandos Locais (Cmd IPC) ────────┤  [Janela Flutuante]
             │      /run/user/$UID/tasknotes-pomodoro.cmd  │  (Play/Pause/Stop)
             │                                         │
             │◄───── Protocolo Desktop / Foco Niri ────┤  (Trocar / Abrir Tarefa)
             │      obsidian://tasknotes-pomodoro?cmd= │
             ▼                                         ▼
┌───────────────────────────────────────────────────────────────────┐
│                    Niri Wayland Compositor                        │
│            (Regras de Janela Flutuante + Blur GPU)                │
└───────────────────────────────────────────────────────────────────┘
```

---

## Estrutura do Repositório

```text
dms-tasknotes-pomodoro/
├── dms-plugin/               # Plugin composite do DMS (QML)
│   ├── plugin.json           # Manifesto e capacidades do DMS
│   ├── PomodoroDaemon.qml    # Daemon de estado, IPC e janela flutuante
│   ├── PomodoroBarWidget.qml # Widget em formato de pill para a DankBar
│   └── PomodoroSettings.qml  # Painel de configurações no DMS
├── obsidian-plugin/          # Plugin de ponte para o Obsidian
│   ├── manifest.json         # Manifesto do plugin da comunidade
│   └── main.js               # Sincronização em RAM e manipulador de protocolo
├── niri/
│   └── windowrules.kdl       # Regra KDL para janela flutuante fosca com blur
├── install.sh                # Script de instalação automatizada
├── LICENSE                   # Licença MIT
└── README.md
```

---

## Instalação

### 1. Clonar o repositório

```bash
git clone https://github.com/bbarrosdavi/dms-tasknotes-pomodoro.git
cd dms-tasknotes-pomodoro
```

### 2. Executar o instalador

```bash
./install.sh
```

O script criará o link simbólico do plugin do DMS em `~/.config/DankMaterialShell/plugins/tasknotesPomodoro` e detectará seu vault ativo do Obsidian para instalar a ponte.

### 3. Configurar a Janela Flutuante no Niri

Adicione a seguinte regra ao seu arquivo de regras do Niri (por exemplo, em `~/.config/niri/dms/windowrules.kdl` ou `~/.config/niri/config.kdl`):

```kdl
window-rule {
    match title=r#"^Pomodoro - TaskNotes"#
    open-floating true
    default-column-width { fixed 360; }
    default-window-height { fixed 280; }
    geometry-corner-radius 10
    clip-to-geometry true
    background-effect {
        blur true
    }
}
```

Valide a configuração do compositor com `niri validate`.

### 4. Ativar no Dank Material Shell

No arquivo `~/.config/DankMaterialShell/plugin_settings.json`, confirme a ativação:

```json
{
  "tasknotesPomodoro": {
    "enabled": true
  }
}
```

E adicione o widget na sua barra em `~/.config/DankMaterialShell/settings.json`:

```json
"rightWidgets": [
  {
    "id": "tasknotesPomodoro",
    "enabled": true
  }
]
```

Reinicie o DMS para carregar os módulos:

```bash
dms restart
```

### 5. Ativar no Obsidian

No Obsidian, abra **Settings -> Community plugins** e ative o plugin **TaskNotes DMS Bridge**.

---

## Controle via Linha de Comando (IPC)

O plugin expõe comandos utilizáveis em scripts ou atalhos do Niri:

| Comando | Descrição |
|---|---|
| `dms ipc call tasknotesPomodoro toggle` | Abre ou colapsa a janela flutuante |
| `dms ipc call tasknotesPomodoro playPause` | Inicia ou pausa o timer |
| `dms ipc call tasknotesPomodoro switchTask` | Foca o Obsidian e abre a seleção de tarefas |
| `dms ipc call tasknotesPomodoro openTask` | Foca o Obsidian e abre a tarefa ativa |

Exemplo de atalho no `binds.kdl` do Niri:

```kdl
Mod+Shift+P { spawn "dms" "ipc" "call" "tasknotesPomodoro" "toggle"; }
```

---

## Licença

Distribuído sob a licença MIT. Consulte `LICENSE` para mais detalhes.
