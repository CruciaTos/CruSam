// lib/core/updater/version_constants.dart

/// GitHub repository that hosts Crusam releases.
///
/// This is the single place the owner/repo pair is declared. Anything that
/// needs to talk to GitHub about releases (update checks, download URLs,
/// release page links) should derive from these two constants instead of
/// hardcoding "CruciaTos/CruSam" again elsewhere.
const String kGitHubRepoOwner = 'CruciaTos';
const String kGitHubRepoName = 'CruSam';

/// GitHub REST API endpoint that returns the most recently published
/// (non-draft, non-prerelease) release for the repo above.
///
/// https://docs.github.com/en/rest/releases/releases#get-the-latest-release
const String kLatestReleaseApiUrl =
    'https://api.github.com/repos/$kGitHubRepoOwner/$kGitHubRepoName/releases/latest';

/// Filename convention the installer asset attached to a GitHub release
/// must follow in order to be discovered automatically, e.g.
/// `CruSam-Setup-1.2.0.exe`. See [UpdateService] for the matching logic.
const String kInstallerAssetPrefix = 'CruSam-Setup-';
const String kInstallerAssetExtension = '.exe';