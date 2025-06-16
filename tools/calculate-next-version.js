#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const recommendedBump = require('conventional-recommended-bump');
const semver = require('semver');

// Read current version from VERSION file
const versionFile = path.resolve(__dirname, '../VERSION');
if (!fs.existsSync(versionFile)) {
    console.error('VERSION file not found');
    process.exit(1);
}
const currentVersion = fs.readFileSync(versionFile, 'utf8').trim();

recommendedBump({ preset: 'conventionalcommits' }, (err, result) => {
    if (err) {
        console.error('Error determining recommended bump:', err);
        process.exit(1);
    }
    const releaseType = result.releaseType;
    if (!releaseType) {
        // No relevant commits, keep current version
        console.log(currentVersion);
        process.exit(0);
    }
    const nextVersion = semver.inc(currentVersion, releaseType);
    if (!nextVersion) {
        console.error('Failed to increment version');
        process.exit(1);
    }
    console.log(nextVersion);
});
