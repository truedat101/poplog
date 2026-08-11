/* Jenkinsfile — CI for the pop11 Claude-skill tarballs.
 *
 * Topology: ONE Jenkins node does everything.
 *   The x86_64 Linux builder runs its own package/verify natively; every
 *   other platform is built by ssh'ing from that builder into the board
 *   (tools/ci/build-remote.sh) and copying the tarball back.  The boards
 *   need no Jenkins agent, no JVM and no inbound connection from the
 *   controller — just sshd, cc, make, curl and tar.  Small SBCs make poor
 *   Jenkins nodes (agent JVM RAM, flaky reconnects, wedged executors that
 *   then steal unrelated jobs); this keeps them as plain build targets.
 *
 * What it does
 *   Package: tools/ci/build-and-verify.sh builds the engine (corepop seed
 *            -> make all) if the workspace doesn't already have one,
 *            packages the relocatable tarball, verifies its contents, and
 *            runs the real installer + a live session smoke test in a
 *            sandbox HOME.  Remote platforms run the same script on the
 *            far side of the ssh connection.
 *   Publish: (opt-in via the PUBLISH parameter) regenerates
 *            SHA256SUMS.pop11-skill over the tarballs collected in dist/
 *            and uploads them to the GitHub release with --clobber.
 *
 * Jenkins-side setup (nothing machine-specific belongs in this file):
 *   - Node: one agent labelled "poplog linux x86_64".  Prerequisites: git,
 *     curl, cc/make, ssh/scp (plus the build deps in INSTALL: ncurses dev,
 *     libcurl and libsqlite3 dev headers for the shims).  The gh CLI is
 *     needed only for PUBLISH.
 *   - Remote targets: the builder's own ~/.ssh/config and keys decide what
 *     "raspi5" or "riscv-cloud" mean.  Hostnames, IPs, ports and users stay
 *     on the builder, never in the repo; the REMOTE_* parameters below take
 *     only the alias.  An empty parameter skips that platform.
 *   - Credential: a GitHub token with release-assets write access, stored
 *     as a Jenkins "Secret text" credential with ID `github-release-token`.
 *     It is only ever exposed to the publish step via withCredentials and
 *     read by gh from the environment — never echoed, never a parameter.
 */
pipeline {
    /* every stage runs here; remote platforms are ssh targets, not nodes */
    agent { label 'poplog && linux && x86_64' }
    options {
        timestamps()
        disableConcurrentBuilds()
        /* a from-seed riscv64 build is slow; this covers all platforms */
        timeout(time: 180, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }
    parameters {
        booleanParam(name: 'PUBLISH', defaultValue: false,
            description: 'Upload the tarballs + checksums to the GitHub release')
        string(name: 'RELEASE_TAG', defaultValue: 'v160200-skill',
            description: 'Release tag to upload assets to (publish only)')
        booleanParam(name: 'FORCE_ENGINE_REBUILD', defaultValue: false,
            description: 'Rebuild the Poplog engine even if the workspace has one')
        /* ssh aliases as known to the builder; empty => skip that platform.
         * arm64 is parked empty on purpose: the Pi 5 auto-build is off
         * until its board is back in the loop.  Set it to "raspi5" (or
         * whatever the builder's ssh config calls it) to turn it on again. */
        string(name: 'REMOTE_ARM64', defaultValue: '',
            description: 'ssh alias of an arm64 Linux board (e.g. raspi5); empty = skip')
        string(name: 'REMOTE_RISCV64', defaultValue: 'riscv-cloud',
            description: 'ssh alias of a riscv64 Linux host; empty = skip')
        string(name: 'REMOTE_MACOS', defaultValue: '',
            description: 'ssh alias of a macOS arm64 host; empty = skip')
    }
    environment {
        FORCE_ENGINE_REBUILD = "${params.FORCE_ENGINE_REBUILD ? 1 : 0}"
    }
    stages {
        stage('Package') {
            parallel {
                stage('linux-x86_64') {
                    steps {
                        sh 'sh tools/ci/build-and-verify.sh dist'
                    }
                }
                stage('linux-arm64') {
                    when { expression { params.REMOTE_ARM64?.trim() } }
                    steps {
                        sh "sh tools/ci/build-remote.sh '${params.REMOTE_ARM64}' dist"
                    }
                }
                stage('linux-riscv64') {
                    when { expression { params.REMOTE_RISCV64?.trim() } }
                    steps {
                        sh "sh tools/ci/build-remote.sh '${params.REMOTE_RISCV64}' dist"
                    }
                }
                stage('macos-arm64') {
                    when { expression { params.REMOTE_MACOS?.trim() } }
                    steps {
                        sh "sh tools/ci/build-remote.sh '${params.REMOTE_MACOS}' dist"
                    }
                }
            }
            post {
                success {
                    archiveArtifacts artifacts: 'dist/pop11-skill-*.tar.gz',
                                     fingerprint: true
                }
            }
        }
        stage('Publish') {
            when { expression { params.PUBLISH } }
            steps {
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
