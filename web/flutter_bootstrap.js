{{flutter_js}}
{{flutter_build_config}}

const buildVersion = {{flutter_service_worker_version}};
const bootShell = document.getElementById('boot-shell');
const bootStatus = document.getElementById('boot-status');
const searchParams = new URLSearchParams(window.location.search);
const renderer = searchParams.get('renderer');

if (_flutter.buildConfig?.builds) {
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) {
      build.mainJsPath = `${build.mainJsPath}?v=${buildVersion}`;
    }
  }
}

function setBootStatus(message) {
  if (bootStatus) {
    bootStatus.textContent = message;
  }
}

_flutter.loader
  .load({
    config: renderer ? {renderer} : {},
    onEntrypointLoaded: async function (engineInitializer) {
      setBootStatus('Starting Immich TV…');
      const appRunner = await engineInitializer.initializeEngine();
      setBootStatus('Rendering…');
      await appRunner.runApp();
      if (bootShell) {
        window.setTimeout(() => bootShell.remove(), 0);
      }
    },
  })
  .catch((error) => {
    console.error('Flutter bootstrap failed.', error);
    setBootStatus(
      'The web app could not start on this device. Please reload and try again.'
    );
  });
