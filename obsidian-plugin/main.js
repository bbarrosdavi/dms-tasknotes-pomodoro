const { Plugin } = require("obsidian");
const fs = require("fs");
const path = require("path");

const UID = typeof process.getuid === "function" ? process.getuid() : 1000;
const STATE_FILE = `/run/user/${UID}/tasknotes-pomodoro.json`;
const CMD_FILE = `/run/user/${UID}/tasknotes-pomodoro.cmd`;

module.exports = class TasknotesDmsBridge extends Plugin {
  async onload() {
    this.cmdCheckInterval = null;
    this.heartbeatInterval = null;
    this.listeners = [];

    // Register protocol handler for obsidian://tasknotes-pomodoro?cmd=...
    this.registerObsidianProtocolHandler("tasknotes-pomodoro", async (params) => {
      await this.handleProtocolCommand(params);
    });

    // Setup command file checking
    this.setupCmdFileWatcher();

    // Hook into TaskNotes when ready
    this.app.workspace.onLayoutReady(() => {
      this.hookTasknotes();
    });
  }

  onunload() {
    if (this.cmdCheckInterval) {
      clearInterval(this.cmdCheckInterval);
      this.cmdCheckInterval = null;
    }
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
    this.cleanupListeners();
    try {
      if (fs.existsSync(STATE_FILE)) {
        // Mark as disconnected
        const raw = fs.readFileSync(STATE_FILE, "utf8");
        const data = JSON.parse(raw);
        data.isRunning = false;
        data.isAvailable = false;
        fs.writeFileSync(STATE_FILE, JSON.stringify(data, null, 2));
      }
    } catch (e) {}
  }

  getTasknotesPlugin() {
    return this.app.plugins?.plugins?.["tasknotes"] || null;
  }

  hookTasknotes() {
    const tn = this.getTasknotesPlugin();
    if (!tn) {
      setTimeout(() => this.hookTasknotes(), 1500);
      return;
    }

    this.cleanupListeners();

    if (tn.emitter) {
      const onTick = () => this.writeState();
      const onStart = () => this.writeState();
      const onComplete = () => this.writeState();
      const onInterrupt = () => this.writeState();
      const onData = () => this.writeState();
      const onTaskUpdated = () => this.writeState();

      tn.emitter.on("pomodoro-tick", onTick);
      tn.emitter.on("pomodoro-start", onStart);
      tn.emitter.on("pomodoro-complete", onComplete);
      tn.emitter.on("pomodoro-interrupt", onInterrupt);
      tn.emitter.on("data-changed", onData);
      tn.emitter.on("task-updated", onTaskUpdated);

      this.listeners.push(
        { emitter: tn.emitter, event: "pomodoro-tick", fn: onTick },
        { emitter: tn.emitter, event: "pomodoro-start", fn: onStart },
        { emitter: tn.emitter, event: "pomodoro-complete", fn: onComplete },
        { emitter: tn.emitter, event: "pomodoro-interrupt", fn: onInterrupt },
        { emitter: tn.emitter, event: "data-changed", fn: onData },
        { emitter: tn.emitter, event: "task-updated", fn: onTaskUpdated }
      );
    }

    // Heartbeat every 2 seconds
    if (!this.heartbeatInterval) {
      this.heartbeatInterval = setInterval(() => this.writeState(), 2000);
    }

    this.writeState();
  }

  cleanupListeners() {
    for (const item of this.listeners) {
      try {
        if (typeof item.emitter.offref === "function") {
          item.emitter.offref(item.fn);
        } else if (typeof item.emitter.off === "function") {
          item.emitter.off(item.event, item.fn);
        }
      } catch (e) {}
    }
    this.listeners = [];
  }

  getState() {
    const tn = this.getTasknotesPlugin();
    if (!tn) {
      return { isAvailable: false, isRunning: false, timeRemaining: 0, timestamp: Date.now() };
    }

    const pomo = tn.pomodoroService;
    const state = pomo ? pomo.getState() : {};
    const session = state.currentSession;
    const isRunning = Boolean(state.isRunning);
    const timeRemaining = typeof state.timeRemaining === "number" ? Math.max(0, state.timeRemaining) : 0;
    const sessionType = session?.type || state.nextSessionType || "work";

    let taskPath = session?.taskPath || pomo?.lastSelectedTaskPath || "";
    let taskTitle = "";
    if (taskPath) {
      const file = this.app.vault.getAbstractFileByPath(taskPath);
      if (file) {
        const cache = this.app.metadataCache.getFileCache(file);
        taskTitle = cache?.frontmatter?.title || file.basename;
      } else {
        taskTitle = path.basename(taskPath, ".md");
      }
    }

    const workDur = tn.settings?.pomodoroWorkDuration || 25;
    const shortBreakDur = tn.settings?.pomodoroShortBreakDuration || 5;
    const longBreakDur = tn.settings?.pomodoroLongBreakDuration || 10;
    const plannedDuration = session?.plannedDuration || (sessionType === "short-break" ? shortBreakDur : sessionType === "long-break" ? longBreakDur : workDur);

    return {
      isAvailable: true,
      isRunning,
      timeRemaining,
      sessionType,
      taskPath,
      taskTitle,
      plannedDuration,
      workDuration: workDur,
      shortBreakDuration: shortBreakDur,
      longBreakDuration: longBreakDur,
      activePeriods: session?.activePeriods || [],
      timestamp: Date.now()
    };
  }

  writeState() {
    try {
      const data = this.getState();
      fs.writeFileSync(STATE_FILE, JSON.stringify(data, null, 2), "utf8");
    } catch (e) {
      console.error("[TasknotesDmsBridge] Error writing state:", e);
    }
  }

  setupCmdFileWatcher() {
    if (this.cmdCheckInterval) clearInterval(this.cmdCheckInterval);
    this.cmdCheckInterval = setInterval(() => {
      try {
        if (fs.existsSync(CMD_FILE)) {
          const raw = fs.readFileSync(CMD_FILE, "utf8").trim();
          fs.unlinkSync(CMD_FILE);
          if (raw) {
            this.handleLocalCommand(raw);
          }
        }
      } catch (e) {}
    }, 200);
  }

  async handleLocalCommand(cmdStr) {
    let cmd = cmdStr;
    let pathArg = "";
    try {
      if (cmdStr.startsWith("{")) {
        const obj = JSON.parse(cmdStr);
        cmd = obj.cmd || obj.action || "";
        pathArg = obj.path || "";
      }
    } catch (e) {}

    const tn = this.getTasknotesPlugin();
    if (!tn) return;
    const pomo = tn.pomodoroService;

    switch (cmd) {
      case "play-pause":
      case "toggle":
        if (pomo) {
          if (pomo.state.isRunning) {
            await pomo.pausePomodoro();
          } else if (pomo.state.currentSession) {
            await pomo.resumePomodoro();
          } else {
            await pomo.startPomodoro();
          }
        }
        break;
      case "pause":
        if (pomo && pomo.state.isRunning) await pomo.pausePomodoro();
        break;
      case "resume":
        if (pomo && !pomo.state.isRunning && pomo.state.currentSession) await pomo.resumePomodoro();
        break;
      case "start":
        if (pomo && !pomo.state.isRunning) await pomo.startPomodoro();
        break;
      case "stop":
        if (pomo) await pomo.stopPomodoro();
        break;
      case "skip-break":
        if (pomo) {
          if (typeof pomo.skipBreak === "function") {
            await pomo.skipBreak();
          } else {
            await pomo.stopPomodoro();
            await pomo.startPomodoro();
          }
        }
        break;
      case "select-task":
        await this.triggerTaskSelection();
        break;
      case "open-task":
        if (pathArg) {
          await this.openTaskFile(pathArg);
        }
        break;
    }
    this.writeState();
  }

  async handleProtocolCommand(params) {
    const cmd = params.cmd || params.action || "";
    const pathArg = params.path || "";
    const tn = this.getTasknotesPlugin();
    if (!tn) return;
    const pomo = tn.pomodoroService;

    if (cmd === "open-task") {
      let targetPath = pathArg;
      if (!targetPath && pomo) {
        targetPath = pomo.state?.currentSession?.taskPath || pomo.lastSelectedTaskPath || "";
      }
      if (targetPath) {
        await this.openTaskFile(targetPath);
      }
    } else if (cmd === "select-task") {
      await this.triggerTaskSelection();
    } else if (cmd === "open-pomodoro") {
      if (typeof tn.activatePomodoroView === "function") {
        await tn.activatePomodoroView();
      }
    } else if (cmd === "play-pause" || cmd === "toggle") {
      if (pomo) {
        if (pomo.state.isRunning) await pomo.pausePomodoro();
        else if (pomo.state.currentSession) await pomo.resumePomodoro();
        else await pomo.startPomodoro();
      }
    } else if (cmd === "pause" && pomo) {
      await pomo.pausePomodoro();
    } else if (cmd === "resume" && pomo) {
      await pomo.resumePomodoro();
    } else if (cmd === "start" && pomo) {
      await pomo.startPomodoro();
    } else if (cmd === "stop" && pomo) {
      await pomo.stopPomodoro();
    } else if (cmd === "skip-break" && pomo) {
      if (typeof pomo.skipBreak === "function") await pomo.skipBreak();
      else {
        await pomo.stopPomodoro();
        await pomo.startPomodoro();
      }
    }
    this.writeState();
  }

  async openTaskFile(filePath) {
    try {
      const file = this.app.vault.getAbstractFileByPath(filePath);
      if (file) {
        const leaf = this.app.workspace.getLeaf(false);
        await leaf.openFile(file);
      }
    } catch (e) {
      console.error("[TasknotesDmsBridge] Error opening task file:", e);
    }
  }

  async triggerTaskSelection() {
    const tn = this.getTasknotesPlugin();
    if (!tn) return;

    // Check if pomodoro view leaf is already open
    const pomoLeaves = this.app.workspace.getLeavesOfType("tasknotes-pomodoro-view");
    if (pomoLeaves.length > 0 && pomoLeaves[0].view && typeof pomoLeaves[0].view.openTaskSelector === "function") {
      await this.app.workspace.revealLeaf(pomoLeaves[0]);
      await pomoLeaves[0].view.openTaskSelector();
      return;
    }

    // Try opening task selector modal
    if (typeof tn.openTaskSelectorWithCreate === "function") {
      await tn.openTaskSelectorWithCreate();
    } else if (typeof tn.activatePomodoroView === "function") {
      const leaf = await tn.activatePomodoroView();
      if (leaf && leaf.view && typeof leaf.view.openTaskSelector === "function") {
        await leaf.view.openTaskSelector();
      }
    }
  }
};
