/* Jenkinsfile — CI for the pop11 Claude-skill tarballs.
 *
 * What it does
 *   Package: on each platform agent, tools/ci/build-and-verify.sh builds
 *            the engine (corepop seed -> make all) if the workspace doesn't
 *            already have one, packages the relocatable tarball, verifies
 *            its contents, and runs the real installer + a live session
 *            smoke test in a sandbox HOME.
 *   Publish: (opt-in via the PUBLISH parameter) regenerates
 *            SHA256SUMS.pop11-skill over all tarballs and uploads them to
 *            the GitHub release with --clobber.
 *
 * Jenkins-side setup (nothing machine-specific belongs in this file):
 *   - Agents: label them with generic capabilities only — e.g.
 *     "poplog linux x86_64" / "poplog macos arm64". Hostnames, IPs and
 *     users live in the Jenkins node config, never in the repo.
 *   - Agent prerequisites: git, curl, cc/make (plus the build deps in
 *     INSTALL: ncurses dev; on Linux also libcurl and libsqlite3 dev
 *     headers for the shims). Publish agent additionally needs the gh CLI.
 *   - Credential: a GitHub token with release-assets write access, stored
 *     as a Jenkins "Secret text" credential with ID `github-release-token`.
 *     It is only ever exposed to the publish step via withCredentials and
 *     read by gh from the environment — never echoed, never a parameter.
 */
pipeline {
    agent none
    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 90, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }
    parameters {
        booleanParam(name: 'PUBLISH', defaultValue: false,
            description: 'Upload the tarballs + checksums to the GitHub release')
        string(name: 'RELEASE_TAG', defaultValue: 'v160200-skill',
            description: 'Release tag to upload assets to (publish only)')
        booleanParam(name: 'FORCE_ENGINE_REBUILD', defaultValue: false,
            description: 'Rebuild the Poplog engine even if the workspace has one')
    }
    stages {
        stage('Package') {
            parallel {
                stage('linux-x86_64') {
                    agent { label 'poplog && linux && x86_64' }
                    steps {
                        sh "FORCE_ENGINE_REBUILD=${params.FORCE_ENGINE_REBUILD ? 1 : 0} " +
                           'sh tools/ci/build-and-verify.sh dist'
                        stash name: 'tarball-linux-x86_64',
                              includes: 'dist/pop11-skill-*.tar.gz'
                        archiveArtifacts artifacts: 'dist/pop11-skill-*.tar.gz',
                                         fingerprint: true
                    }
                }
                stage('macos-arm64') {
                    agent { label 'poplog && macos && arm64' }
                    steps {
                        sh "FORCE_ENGINE_REBUILD=${params.FORCE_ENGINE_REBUILD ? 1 : 0} " +
                           'sh tools/ci/build-and-verify.sh dist'
                        stash name: 'tarball-macos-arm64',
                              includes: 'dist/pop11-skill-*.tar.gz'
                        archiveArtifacts artifacts: 'dist/pop11-skill-*.tar.gz',
                                         fingerprint: true
                    }
                }
            }
        }
        stage('Publish') {
            when { expression { params.PUBLISH } }
            agent { label 'poplog && linux' }
            steps {
                unstash 'tarball-linux-x86_64'
                unstash 'tarball-macos-arm64'
                sh '''
                    cd dist
                    sha256sum pop11-skill-*.tar.gz > SHA256SUMS.pop11-skill
                    cat SHA256SUMS.pop11-skill
                '''
                withCredentials([string(credentialsId: 'github-release-token',
                                        variable: 'GH_TOKEN')]) {
                    sh '''
                        cd dist
                        gh release upload "$RELEASE_TAG" \
                            pop11-skill-*.tar.gz SHA256SUMS.pop11-skill \
                            --clobber -R IoTone/poplog
                        gh release view "$RELEASE_TAG" -R IoTone/poplog \
                            --json assets \
                            -q '.assets[] | .name + "  " + .updatedAt'
                    '''
                }
            }
        }
    }
}
