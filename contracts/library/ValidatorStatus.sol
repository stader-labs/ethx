pragma solidity ^0.8.16;

enum ValidatorStatus {
    INITIALIZED,
    PRE_DEPOSIT,
    DEPOSITED,
    IN_ACTIVATION_QUEUE,
    ACTIVE,
    IN_EXIT_QUEUE,
    EXITED,
    WITHDRAWN
}
