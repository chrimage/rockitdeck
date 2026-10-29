"""Focused, host-safe checks. Integration acceptance uses a disposable VM."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

try:
    import yaml
except ImportError:
    yaml = None

ROOT = Path(__file__).resolve().parents[1]


class InstallerArguments(unittest.TestCase):
    script = 'install.sh'

    def run_script(self, *args):
        # Only argument-rejection and help paths are run; none reach the root check.
        return subprocess.run(['bash', str(ROOT / self.script), *args], stdin=subprocess.DEVNULL,
                              text=True, capture_output=True, timeout=5, start_new_session=True)

    def test_help_is_available_without_root(self):
        result = self.run_script('--help')
        self.assertEqual(result.returncode, 0)
        self.assertIn('Usage: install.sh', result.stdout)
        for flag in ('--owner', '--repository', '--channel', '--enable-updates',
                     '--disable-updates', '--noninteractive'):
            self.assertIn(flag, result.stdout)

    def test_streamed_install_contract(self):
        text = (ROOT / 'install.sh').read_text()
        self.assertIn('default_repository=https://github.com/chrimage/rockitdeck.git', text)
        self.assertEqual(text.rstrip().splitlines()[-1], 'main "$@"')
        self.assertIn('\nmain() {', text)
        self.assertIn('/dev/tty', text)
        self.assertIn('--noninteractive', text.split('No terminal available')[1].split('\n')[0])
        for line in text.replace('\\\n', ' ').splitlines():
            if line.lstrip().startswith(('printf', '#')):
                continue
            if 'read -r' in line and 'IFS=' not in line:
                self.assertIn('-u 8', line)
            if line.lstrip().startswith(('apt-get', 'ansible-pull')):
                self.assertIn('</dev/null', line)

    def test_invalid_arguments_rejected_before_system_changes(self):
        for args in (('--channel', 'nightly'), ('--owner',), ('--unknown',),
                     ('--enable-updates', '--disable-updates'), ('--repository', '--noninteractive')):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_shell_syntax(self):
        subprocess.run(['bash', '-n', str(ROOT / self.script)], check=True)

    def test_boot_service_is_optional_and_bounded(self):
        unit = (ROOT / 'roles/deployment/templates/rockitdeck-update.service.j2').read_text()
        for required in ('Before=display-manager.service', 'WantedBy=graphical.target',
                         'TimeoutStartSec=', 'TimeoutStopSec=', '--only-if-changed',
                         '/usr/bin/flock --nonblock /run/lock/rockitdeck.lock'):
            self.assertIn(required, unit)
        self.assertNotIn('Requires=', unit)
        self.assertNotIn('network-online.target', unit)
        self.assertNotIn('reboot', unit.lower())


class WriterSessionConfiguration(unittest.TestCase):
    @unittest.skipUnless(shutil.which('dconf'), 'dconf is not installed')
    def test_writer_dconf_compiles(self):
        # Copy to a temporary directory so the compile never touches host dconf databases.
        source = ROOT / 'roles/writing_session/files/writer.dconf'
        with tempfile.TemporaryDirectory() as tmp:
            shutil.copy(source, Path(tmp) / '00-writing')
            output = Path(tmp) / 'db'
            result = subprocess.run(['dconf', 'compile', str(output), tmp],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.is_file())

    @unittest.skipUnless(yaml, 'PyYAML is not installed')
    def test_writer_profile_content_is_exact(self):
        tasks = yaml.safe_load((ROOT / 'roles/writing_session/tasks/main.yml').read_text())
        task = next(t for t in tasks if t.get('name') == 'Select writer-only dconf profile')
        self.assertEqual(task['ansible.builtin.copy']['content'], 'DCONF_PROFILE=rockitdeck\n')


if __name__ == '__main__':
    unittest.main()
