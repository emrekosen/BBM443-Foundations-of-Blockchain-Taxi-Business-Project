// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.8.0;


contract TaxiBusiness {
    
    /**
     * struct for drivers
     * holds address,salary, currentBalance, approvalState and lastSalaryTime of driver
     */
    struct Driver {
        address payable id;
        uint salary;
        uint currentBalance;
        uint approvalState;
        bool isApproved;
        uint lastSalaryTime;
    }
    
    /**
     * struct for proposals
     * holds 32 digit id, price, valid time and approval state
     */
    struct Proposal {
        uint32 id;
        uint price;
        uint validTime;
        uint approvalState;
    }
    
    /**
     * struct for participants
     * holds address of participant and balance
     */
    struct Participant{
        address adr;
        uint balance;
    }
    
    // addresses - participant mapping
    mapping (address => Participant) participants;
    
    // list of addresses of participants to use in vote counting
    address[] participantsAddresses;
    
    // address of manager
    address private manager;
    
    // current driver of taxi
    Driver taxiDriver;
    
    // the car dealer
    address payable carDealer;
    
    // current total money in cotract that has not been distributed
    uint balance;
    
    // total amount for maintenance and tax, fixed 10 Ether
    uint maintenanceFee;
    
    // last maintenance time for checking 6 months period
    uint lastMaintenance;
    
    // last divident pay time
    uint lastDividentPay;
    
    // amount that participants needs to pay for entering business, fixed 100 Ether
    uint participationFee;
    
    // the 32 digit number ID of car
    uint112 carID;
    
    // proposed car by the car dealer
    Proposal proposedCar;
    
    // proposal for car repurchase by the car dealer
    Proposal proposedRepurchase;
    
    // votes for current proposal, used for check user whether voted or not
    mapping (address => bool) driverVotes;
    mapping (address => bool) carVotes;
    mapping (address => bool) repurchaseVotes;
    
    // modifier to check if caller is manager
    modifier isManager() {
        require(msg.sender == manager, "Caller is not manager");
        _;
    }
    
    // modifier to check if caller is car dealer
    modifier isCarDealer() {
        require(msg.sender == carDealer, "Caller is not car dealer");
        _;
    }
    
    // modifier to check if caller is participant
    modifier isParticipant() {
        require(participants[msg.sender].adr != address(0), "Caller is not participant");
        _;
    }
    
    // modifier to check if caller is driver
    modifier isDriver() {
        require(msg.sender == taxiDriver.id, "Caller is not driver");
        _;
    }
    
    constructor() {
        manager = msg.sender;
        balance = 0;
        maintenanceFee = 10 ether;
        lastMaintenance = block.timestamp;
        lastDividentPay = block.timestamp;
        participationFee = 100 ether;

    }
    
    
    /**
     * max 9 participants can join
     * caller of this function must pay 100 or more ether
     * excess ether will be returned
     */
    function join() public payable {
        require(participantsAddresses.length < 9, "No more place to join");
        require(participants[msg.sender].adr == address(0), "You already joined");
        require(msg.value >= participationFee, "Not enough ether to join");
        participants[msg.sender] = Participant(msg.sender, 0 ether);
        participantsAddresses.push(msg.sender);
        balance += participationFee;
        uint refund = msg.value - participationFee;
        if(refund > 0) msg.sender.transfer(refund);
    }
    
    
    /**
     * only manager can call this function
     * sets carDealer
     */
    function setCarDealer(address payable newCarDealer) public isManager {
        carDealer = newCarDealer;
    }
    
    /**
     * proposes car to business
     * only car dealer can call this function
     * resets all votes in votes list with resetVotes modifier
    */
    function carProposeToBusiness(uint32 id, uint price, uint validTime) public isCarDealer{
        require(carID == 0, "There is already a car in business");
        proposedCar = Proposal(id, price, validTime, 0);
        
         for(uint i = 0; i < participantsAddresses.length; i++){
            carVotes[participantsAddresses[i]] = false;
        }
    }
    
    /**
     * approve current car propose
     * only participants can call this function 
     */
    function approvePurchaseCar() public isParticipant {
        require(!carVotes[msg.sender], "You already voted");
        proposedCar.approvalState += 1;
        carVotes[msg.sender] = true;
    }
    
    /**
     * purchases proposed car and sends ether to car dealer
     * only manager can call this function
     */
    function purchaseCar() public isManager {
        require(balance >= proposedCar.price, "The business don't have enough ether");
        require(block.timestamp <= proposedCar.validTime, "The valid time exceeded");
        require(proposedCar.approvalState > (participantsAddresses.length / 2), "The proposal didn't approved more than half of the business");
        balance -= proposedCar.price;
        if(!carDealer.send(proposedCar.price)){
            balance += proposedCar.price;
            revert();
        }
        carID = proposedCar.id;
    }
    
    /**
     * the car dealer proposes a repurchase for car in current car
     * only car dealer can call this function
     * resets votes for new voting
     */
    function repurchaseCarPropose(uint32 id, uint price, uint validTime) public isCarDealer{
        require(carID == id, "This is not the businesses car");
        proposedRepurchase = Proposal(id, price, validTime, 0);
         for(uint i = 0; i < participantsAddresses.length; i++){
            repurchaseVotes[participantsAddresses[i]] = false;
        }
    }
    
    /**
     * approves current car repurchase proposal
     * only participants can call this function
     */
    function approveSellProposal() public isParticipant {
        require(!repurchaseVotes[msg.sender], "You already voted");
        proposedRepurchase.approvalState += 1;
        repurchaseVotes[msg.sender] = true;
    }
    
    /**
     * repurchases current car
     * only car dealer can call this function
     */
    function repurchaseCar() public payable isCarDealer {
        require(block.timestamp <= proposedRepurchase.validTime, "The valid time exceeded");
        require(proposedRepurchase.approvalState > (participantsAddresses.length / 2), "The proposal didn't approved more than half of the business");
        require(msg.value >= proposedRepurchase.price, "The sent ether is not enough");
        uint refund =  msg.value - proposedRepurchase.price;
        if(refund > 0) msg.sender.transfer(refund);
        balance += msg.value - refund;
        delete carID;
    }
    
    /**
     * proposes a driver
     * only manager can call this function
     * resets votes for new voting
     */
    function proposeDriver(address payable driverAddress, uint salary) public isManager{
        require(!taxiDriver.isApproved, "There is a taxi driver already!");
        taxiDriver = Driver(driverAddress, salary, 0, 0, false, block.timestamp);
         for(uint i = 0; i < participantsAddresses.length; i++){
            driverVotes[participantsAddresses[i]] = false;
        }
    }
    
    /**
     * approves proposed driver
     * only participants can call this function
     */
    function approveDriver() public isParticipant {
        require(!driverVotes[msg.sender], "You already voted");
        taxiDriver.approvalState += 1;
        driverVotes[msg.sender] = true;
    }
    
    /**
     * sets driver
     * only manager can call this function
     */
    function setDriver() public isManager {
        require(!taxiDriver.isApproved, "There is a taxi driver already!");
        require(taxiDriver.id != address(0), "There is no driver");
        require(taxiDriver.approvalState > (participantsAddresses.length / 2), "The driver didn't approved more than half of the business");
        taxiDriver.isApproved = true;
    }
    
    /**
     * fires current driver and sends his/her balance
     * only manager can call this function
     */
    function fireDriver() public isManager {
        require(taxiDriver.isApproved, "There is no driver!");
        balance -= taxiDriver.salary;
        if(!taxiDriver.id.send(taxiDriver.salary)){
            balance += taxiDriver.salary;
            revert();
        }
        
        delete taxiDriver;
    }
    
    /**
     * customers call this function to pay charge
     */
    function payTaxiCharge() public payable {
        balance += msg.value;
    }
    
    /**
     * adds monthly salary to drivers balance
     * only manager can call this function
     */
    function releaseSalary() public isManager {
        require(taxiDriver.isApproved, "There is no taxi driver");
        require(balance >= taxiDriver.salary, "Not enough balance to pay driver salary");
        require(block.timestamp - taxiDriver.lastSalaryTime >= 2629743, "1 month has not passed since the last payment");
        balance -= taxiDriver.salary;
        taxiDriver.currentBalance += taxiDriver.salary;
        taxiDriver.lastSalaryTime = block.timestamp;
    }
    
    /**
     * sends the drivers balance to drivers account
     * only driver can call this function
     */
    function getSalary() public isDriver {
        require(taxiDriver.currentBalance > 0, "There is no ether in driver balance");
        taxiDriver.id.transfer(taxiDriver.currentBalance);
        // if(!taxiDriver.id.send(taxiDriver.currentBalance)){
        //     revert();
        // }
        taxiDriver.currentBalance = 0;
    }
    
    /**
     * pays 10 ether to car dealer every 6 month
     * only manager can call this function
     */
    function payCarExpenses() public isManager {
        require(block.timestamp - lastMaintenance >= 15778463, "6 month has not passed since the last payment");
        require(carID != 0, "There is no car to pay expense");
        require(balance >= maintenanceFee, "Not enough balance to pay expenses");
        balance -= maintenanceFee;
        if(!carDealer.send(maintenanceFee)){
            balance += maintenanceFee;
            revert();
        }
        lastMaintenance = block.timestamp;
    }
    
    /**
     * sends dividend to each participants balance every 6 months
     * only manager can call this function
     */
    function payDividend() public isManager {
        require(block.timestamp - lastDividentPay >= 15778463, "Dividends paid already");
        require(balance > 0, "Not enough balance");
        require(balance > participationFee * participantsAddresses.length, "There is no profit right now");
        uint dividend = (balance - (participationFee * participantsAddresses.length)) / participantsAddresses.length;
        for(uint i = 0; i < participantsAddresses.length; i++){
            participants[participantsAddresses[i]].balance += dividend;
        }
        balance = 0;
        lastDividentPay = block.timestamp;
    }
    
    /**
     *participants can get their dividend to own account 
     * only participant can call this function
     */
    function getDividend() public payable isParticipant {
        require(participants[msg.sender].balance > 0, "There is no ether in your balance");
        if(!msg.sender.send(participants[msg.sender].balance)){
            revert();
        }
        participants[msg.sender].balance = 0;
    }
    
    /**
     * fallback function
     */
    fallback () external payable {
    }

}