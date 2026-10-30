*** Settings ***
Documentation     Publish version resolution without pushing anything.
...               publish.sh runs in throwaway git repos with a fake `docker`
...               binary on PATH, so no image is ever built or pushed.
Library           OperatingSystem
Library           Process
Library           String
Suite Setup       Run Process    chmod    +x    ${CURDIR}/mocks/docker

*** Variables ***
${PUBLISH}        ${CURDIR}/../publish.sh
${MOCK_DOCKER}    ${CURDIR}/mocks/docker

*** Keywords ***
Fresh Repo
    [Arguments]    ${name}
    ${repo}=    Join Path    ${TEMPDIR}    ${name}
    Remove Directory    ${repo}    recursive=True
    Create Directory    ${repo}
    Run Process    git    init    -q    ${repo}
    Run Process    git    -C    ${repo}    config    user.email    test@example.com
    Run Process    git    -C    ${repo}    config    user.name    Test
    Copy File    ${PUBLISH}    ${repo}/publish.sh
    RETURN    ${repo}

Commit File
    [Arguments]    ${repo}    ${name}=file.txt
    Create File    ${repo}/${name}    content=${name}\n
    Run Process    git    -C    ${repo}    add    -A
    Run Process    git    -C    ${repo}    commit    -qm    ${name}

Publish In
    [Arguments]    ${repo}    ${log}    @{args}
    ${path}=    Catenate    SEPARATOR=:    ${CURDIR}/mocks    %{PATH}
    ${r}=    Run Process    sh    ${repo}/publish.sh    @{args}
    ...    cwd=${repo}    stderr=STDOUT    timeout=60s
    ...    env:PATH=${path}    env:MOCK_LOG=${log}
    RETURN    ${r}

*** Test Cases ***
Exact Tag Publishes Full Floating And Latest
    ${repo}=    Fresh Repo    pub-tag
    Create File    ${repo}/registries    content=example.com:5000/img\n
    Commit File    ${repo}
    Run Process    git    -C    ${repo}    tag    v2.3.4
    ${r}=    Publish In    ${repo}    ${TEMPDIR}/pub-tag.log
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    published 2.3.4
    ${log}=    Get File    ${TEMPDIR}/pub-tag.log
    Should Contain    ${log}    -t example.com:5000/img:2.3.4
    Should Contain    ${log}    -t example.com:5000/img:2.3
    Should Contain    ${log}    -t example.com:5000/img:2
    Should Contain    ${log}    -t example.com:5000/img:latest

Untagged Commit Publishes Edge Never Latest
    ${repo}=    Fresh Repo    pub-edge
    Create File    ${repo}/registries    content=example.com:5000/img\n
    Commit File    ${repo}
    ${sha}=    Run Process    git    -C    ${repo}    rev-parse    --short    HEAD
    ${short}=    Strip String    ${sha.stdout}
    ${r}=    Publish In    ${repo}    ${TEMPDIR}/pub-edge.log
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    published edge
    ${log}=    Get File    ${TEMPDIR}/pub-edge.log
    Should Contain    ${log}    -t example.com:5000/img:edge
    Should Contain    ${log}    -t example.com:5000/img:sha-${short}
    Should Not Contain    ${log}    :latest

CLI Registries Override The File
    ${repo}=    Fresh Repo    pub-args
    Create File    ${repo}/registries    content=example.com:5000/from-file\n
    Commit File    ${repo}
    Run Process    git    -C    ${repo}    tag    v1.0.0
    ${r}=    Publish In    ${repo}    ${TEMPDIR}/pub-args.log    example.com:5000/from-args
    Should Be Equal As Integers    ${r.rc}    0
    ${log}=    Get File    ${TEMPDIR}/pub-args.log
    Should Contain    ${log}    -t example.com:5000/from-args:1.0.0
    Should Not Contain    ${log}    from-file

Dirty Worktree Refuses Without Calling Docker
    ${repo}=    Fresh Repo    pub-dirty
    Create File    ${repo}/registries    content=example.com:5000/img\n
    Commit File    ${repo}
    Create File    ${repo}/uncommitted.txt    content=dirty\n
    Remove File    ${TEMPDIR}/pub-dirty.log
    ${r}=    Publish In    ${repo}    ${TEMPDIR}/pub-dirty.log
    Should Be Equal As Integers    ${r.rc}    1
    Should Contain    ${r.stdout}    dirty worktree
    File Should Not Exist    ${TEMPDIR}/pub-dirty.log

Empty Registry Set Refuses
    ${repo}=    Fresh Repo    pub-noreg
    Create File    ${repo}/registries    content=# nothing configured yet\n
    Commit File    ${repo}
    Remove File    ${TEMPDIR}/pub-noreg.log
    ${r}=    Publish In    ${repo}    ${TEMPDIR}/pub-noreg.log
    Should Be Equal As Integers    ${r.rc}    1
    Should Contain    ${r.stdout}    no registries
    File Should Not Exist    ${TEMPDIR}/pub-noreg.log
