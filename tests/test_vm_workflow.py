"""Host-safe guards for the reusable disposable-VM workflow (no VM launched)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tests/vm/vm.sh'


class VMWorkflowGuards(unittest.TestCase):
    def call(self, action, state, **extra):
        env = dict(os.environ, VM_STATE_DIR=str(state), **extra)
        return subprocess.run(['bash', str(SCRIPT), action], env=env,
                              capture_output=True, text=True, timeout=5)

    def test_shell_syntax(self):
        subprocess.run(['bash', '-n', str(SCRIPT)], check=True)

    def test_installer_user_matches_ssh_and_is_not_reserved_admin(self):
        preseed = (SCRIPT.parent / 'preseed.cfg.in').read_text()
        username = next(line.split()[-1] for line in preseed.splitlines()
                        if line.startswith('d-i passwd/username string '))
        self.assertNotEqual(username, 'admin')  # Debian installer rejects it.
        self.assertIn(username + '@127.0.0.1', SCRIPT.read_text())
        self.assertIn('/home/' + username + '/.ssh', preseed)

    def test_state_inside_repo_rejected(self):
        target = ROOT / 'must-not-be-created'
        result = self.call('fetch', target)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('outside the repository', result.stderr)
        self.assertFalse(target.exists())

    def test_nonempty_unmarked_directory_not_claimed(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            disk = state / 'disk.qcow2'
            disk.write_text('not a test disk')
            result = self.call('fetch', state)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('nonempty', result.stderr)
            self.assertEqual(disk.read_text(), 'not a test disk')
            self.assertFalse((state / '.rockitdeck-vm-state').exists())

    def test_destroy_needs_confirmation_and_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            for extra in ({}, {'VM_DESTROY': 'yes'}):
                result = self.call('destroy', tmp, **extra)
                self.assertNotEqual(result.returncode, 0)

    def test_existing_disk_not_reinstalled(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            (state / '.rockitdeck-vm-state').touch()
            disk = state / 'disk.qcow2'
            disk.write_text('preserve')
            result = self.call('install', state)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('existing disk', result.stderr)
            self.assertEqual(disk.read_text(), 'preserve')

    def test_invalid_port_rejected(self):
        result = self.call('fetch', ROOT.parent / 'unused', VM_SSH_PORT='70000')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('out of range', result.stderr)


if __name__ == '__main__':
    unittest.main()
