pragma solidity ^0.8.16;

enum ValidatorStatus {
    INITIALIZED,
    PRE_DEPOSIT,
    FRONT_RUN,
    DEPOSITED,
    IN_ACTIVATION_QUEUE,
    ACTIVE,
    IN_EXIT_QUEUE,
    EXITED,
    WITHDRAWN
}
