pragma solidity ^0.8.16;

enum ValidatorStatus {
    NOTDEPOSITED,
    PENDING,
    ACTIVE,
    EXITING,
    EXITED,
    WITHDRAWN
}
