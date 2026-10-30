*** Settings ***
Documentation     Funnel logic without touching a real tailnet.
...               A fake `tailscale` binary on PATH records calls and returns
...               canned responses, so no funnel is ever created.
Library           OperatingSystem
Library           Process
Library           String
Suite Setup       Make Mocks Executable

*** Variables ***
${FUNNEL}         ${CURDIR}/../docker/funnel.sh
${MOCK}           ${CURDIR}/mocks/tailscale
${OUT}            ${CURDIR}/out

*** Keywords ***
Funnel Once
    [Arguments]    ${log}    ${mode}=ok    ${extra}=${EMPTY}
    Create Directory    ${OUT}
    Remove File    ${log}
    Create Directory    ${OUT}
    ${cmd}=    Catenate    MOCK_LOG=${log} MOCK_MODE=${mode} TAILSCALE_BIN=${MOCK} ${extra} sh -c '. ${FUNNEL} && funnel_once'
    ${r}=    Run Process    sh    -c    ${cmd}    stderr=STDOUT
    RETURN    ${r}

Make Mocks Executable
    Run Process    chmod    +x    ${CURDIR}/mocks/tailscale
    Run Process    chmod    +x    ${CURDIR}/mocks/containerboot
    Run Process    chmod    +x    ${CURDIR}/mocks/docker

Funnel Append
    [Arguments]    ${log}    ${mode}=ok    ${extra}=${EMPTY}
    ${cmd}=    Catenate    MOCK_LOG=${log} MOCK_MODE=${mode} TAILSCALE_BIN=${MOCK} ${extra} sh -c '. ${FUNNEL} && funnel_once'
    ${r}=    Run Process    sh    -c    ${cmd}    stderr=STDOUT
    RETURN    ${r}

Module Call
    [Arguments]    ${call}    ${log}    ${mode}=ok    ${extra}=${EMPTY}
    Create Directory    ${OUT}
    Remove File    ${log}
    ${cmd}=    Catenate    MOCK_LOG=${log} MOCK_MODE=${mode} TAILSCALE_BIN=${MOCK} ${extra} sh -c '. ${FUNNEL} && ${call}'
    ${r}=    Run Process    sh    -c    ${cmd}    stderr=STDOUT    timeout=30s
    RETURN    ${r}

*** Test Cases ***
Disabled By Default Stays Unpublished And Resets State
    ${r}=    Funnel Once    ${OUT}/disabled.log
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    staying unpublished
    ${log}=    Get File    ${OUT}/disabled.log
    Should Contain    ${log}    funnel reset

Enabled Serves Path To Target
    ${r}=    Funnel Once    ${OUT}/enabled.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    funnel serving / -> localhost:8123
    ${log}=    Get File    ${OUT}/enabled.log
    Should Contain    ${log}    funnel --bg --set-path / localhost:8123

Enabled Without Target Fails Fast
    ${r}=    Funnel Once    ${OUT}/notarget.log    ok    extra=FUNNEL_ENABLED=true
    Should Be Equal As Integers    ${r.rc}    2
    Should Contain    ${r.stdout}    FUNNEL_TARGET is required

Failing Funnel Returns Retry Signal
    ${r}=    Funnel Once    ${OUT}/retry.log    fail-funnel-always    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123
    Should Be Equal As Integers    ${r.rc}    1

Enable Then Disable Leaves No Funnel Behind
    Remove File    ${OUT}/toggle-off.log
    ${a}=    Funnel Append    ${OUT}/toggle-off.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/
    Should Be Equal As Integers    ${a.rc}    0
    Should Contain    ${a.stdout}    funnel serving / -> localhost:8123
    ${b}=    Funnel Append    ${OUT}/toggle-off.log    ok
    Should Be Equal As Integers    ${b.rc}    0
    Should Contain    ${b.stdout}    staying unpublished
    ${log}=    Get File    ${OUT}/toggle-off.log
    Should Contain X Times    ${log}    funnel reset    2
    Should Contain X Times    ${log}    funnel --bg    1

Disable Then Enable Publishes Again
    Remove File    ${OUT}/toggle-on.log
    ${a}=    Funnel Append    ${OUT}/toggle-on.log    ok
    Should Be Equal As Integers    ${a.rc}    0
    Should Contain    ${a.stdout}    staying unpublished
    ${b}=    Funnel Append    ${OUT}/toggle-on.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/
    Should Be Equal As Integers    ${b.rc}    0
    Should Contain    ${b.stdout}    funnel serving / -> localhost:8123
    ${log}=    Get File    ${OUT}/toggle-on.log
    Should Contain X Times    ${log}    funnel reset    2
    Should Contain X Times    ${log}    funnel --bg    1

Changed Target Is Reflected And Old Rule Cleared
    Remove File    ${OUT}/target-change.log
    ${a}=    Funnel Append    ${OUT}/target-change.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/
    Should Be Equal As Integers    ${a.rc}    0
    ${b}=    Funnel Append    ${OUT}/target-change.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:9000 FUNNEL_PATH=/
    Should Be Equal As Integers    ${b.rc}    0
    Should Contain    ${b.stdout}    funnel serving / -> localhost:9000
    ${log}=    Get File    ${OUT}/target-change.log
    Should Contain X Times    ${log}    funnel reset    2
    Should Contain X Times    ${log}    funnel --bg --set-path / localhost:8123    1
    Should Contain X Times    ${log}    funnel --bg --set-path / localhost:9000    1
    Should Match Regexp    ${log}    (?s)localhost:8123.*funnel reset.*localhost:9000

Changed Path Is Reflected And Old Rule Cleared
    Remove File    ${OUT}/path-change.log
    ${a}=    Funnel Append    ${OUT}/path-change.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/old
    Should Be Equal As Integers    ${a.rc}    0
    ${b}=    Funnel Append    ${OUT}/path-change.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/new
    Should Be Equal As Integers    ${b.rc}    0
    Should Contain    ${b.stdout}    funnel serving /new -> localhost:8123
    ${log}=    Get File    ${OUT}/path-change.log
    Should Contain X Times    ${log}    funnel reset    2
    Should Contain X Times    ${log}    funnel --bg --set-path /old localhost:8123    1
    Should Contain X Times    ${log}    funnel --bg --set-path /new localhost:8123    1
    Should Match Regexp    ${log}    (?s)--set-path /old.*funnel reset.*--set-path /new

Reset Retried Then Succeeds Before Serving
    Create Directory    ${OUT}/reset-retry-state
    Remove File    ${OUT}/reset-retry-state/reset_attempts
    ${r}=    Funnel Once    ${OUT}/reset-retry.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/ MOCK_FAIL_RESET=2 MOCK_STATE=${OUT}/reset-retry-state FUNNEL_RESET_DELAY=0
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    funnel serving / -> localhost:8123
    ${log}=    Get File    ${OUT}/reset-retry.log
    Should Contain X Times    ${log}    funnel reset    3
    Should Contain X Times    ${log}    funnel --bg    1

Reset Always Failing Warns Loudly And Stays Unpublished
    Create Directory    ${OUT}/reset-fail-state
    Remove File    ${OUT}/reset-fail-state/reset_attempts
    ${r}=    Funnel Once    ${OUT}/reset-fail.log    ok    extra=MOCK_FAIL_RESET=always MOCK_STATE=${OUT}/reset-fail-state FUNNEL_RESET_RETRIES=3 FUNNEL_RESET_DELAY=0
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    WARNING: funnel reset failed 3 times
    Should Contain    ${r.stdout}    staying unpublished
    ${log}=    Get File    ${OUT}/reset-fail.log
    Should Contain X Times    ${log}    funnel reset    3
    Should Not Contain    ${log}    funnel --bg

Reset Always Failing Still Attempts Serve When Enabled
    Create Directory    ${OUT}/reset-fail-serve-state
    Remove File    ${OUT}/reset-fail-serve-state/reset_attempts
    ${r}=    Funnel Once    ${OUT}/reset-fail-serve.log    ok    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/ MOCK_FAIL_RESET=always MOCK_STATE=${OUT}/reset-fail-serve-state FUNNEL_RESET_RETRIES=3 FUNNEL_RESET_DELAY=0
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    WARNING: funnel reset failed 3 times
    Should Contain    ${r.stdout}    funnel serving / -> localhost:8123

Serve Retried Until Tailnet Approval Then Served Once
    Create Directory    ${OUT}/approval-state
    Remove File    ${OUT}/approval-state/served
    Remove File    ${OUT}/approval-state/reset_attempts
    ${r}=    Module Call    ensure_funnel    ${OUT}/approval.log    fail-serve-once    extra=FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/ MOCK_STATE=${OUT}/approval-state FUNNEL_RETRY_DELAY=0
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    funnel serving / -> localhost:8123
    ${log}=    Get File    ${OUT}/approval.log
    Should Contain X Times    ${log}    funnel --bg    2

Backend Wait Returns Once Running
    Create Directory    ${OUT}/backend-state
    Remove File    ${OUT}/backend-state/status_calls
    ${r}=    Module Call    wait_for_backend    ${OUT}/backend.log    ok    extra=MOCK_STATE=${OUT}/backend-state MOCK_BACKEND_DELAY=2 BACKEND_WAIT_DELAY=0
    Should Be Equal As Integers    ${r.rc}    0
    ${log}=    Get File    ${OUT}/backend.log
    Should Contain X Times    ${log}    status    3

Backend Never Ready Exhausts Attempts
    Create Directory    ${OUT}/noready-state
    Remove File    ${OUT}/noready-state/status_calls
    ${r}=    Module Call    wait_for_backend    ${OUT}/noready.log    no-backend    extra=MOCK_STATE=${OUT}/noready-state BACKEND_WAIT_ATTEMPTS=3 BACKEND_WAIT_DELAY=0
    Should Be Equal As Integers    ${r.rc}    1
    ${log}=    Get File    ${OUT}/noready.log
    Should Contain X Times    ${log}    status    3

Entrypoint Boots Daemon Waits And Serves
    Create Directory    ${OUT}/boot-state
    Remove File    ${OUT}/boot-state/status_calls
    Remove File    ${OUT}/boot.log
    ${cmd}=    Catenate    MOCK_LOG=${OUT}/boot.log TAILSCALE_BIN=${MOCK} CONTAINERBOOT_BIN=${CURDIR}/mocks/containerboot FUNNEL_ENABLED=true FUNNEL_TARGET=localhost:8123 FUNNEL_PATH=/ MOCK_STATE=${OUT}/boot-state sh ${CURDIR}/../docker/entrypoint.sh
    ${r}=    Run Process    sh    -c    ${cmd}    stderr=STDOUT    timeout=30s
    Should Be Equal As Integers    ${r.rc}    0
    Should Contain    ${r.stdout}    funnel serving / -> localhost:8123
    ${log}=    Get File    ${OUT}/boot.log
    Should Contain    ${log}    funnel --bg --set-path / localhost:8123
