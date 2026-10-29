import Meta from 'gi://Meta';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class WritingSession extends Extension {
    enable() {
        this._activities = Main.panel.statusArea.activities;
        this._activities?.container.hide();
        this._showOverview = Main.overview.show;
        Main.overview.hide();
        Main.overview.show = () => {};
        // Shell's startup animation shows the overview without calling show().
        this._startupComplete = Main.layoutManager.connect('startup-complete', () => Main.overview.hide());
        this._windowCreated = global.display.connect('window-created', (_display, window) => {
            // Window app IDs may not be assigned at creation time.
            const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
                this._timers.delete(id);
                this._maximize(window);
                return GLib.SOURCE_REMOVE;
            });
            this._timers.add(id);
        });
        this._timers = new Set();
        global.get_window_actors().forEach(actor => this._maximize(actor.meta_window));
    }

    _maximize(window) {
        if (window?.get_wm_class()?.toLowerCase().includes('zettlr') &&
            window.get_window_type() === Meta.WindowType.NORMAL)
            window.maximize(Meta.MaximizeFlags.BOTH);
    }

    disable() {
        Main.layoutManager.disconnect(this._startupComplete);
        global.display.disconnect(this._windowCreated);
        this._timers.forEach(id => GLib.source_remove(id));
        this._timers.clear();
        Main.overview.show = this._showOverview;
        this._activities?.container.show();
    }
}
