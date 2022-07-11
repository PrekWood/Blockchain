// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol';

contract Shop is IERC20 {
    event E(uint msg);

    string PENDING_REQ = "Pending";
    string ACCEPT_REQ = "Accept";
    string DECLINE_REQ = "Decline";
    string CLIENT_DECLINE_REQ = "User Decline";

    // public data
    address public owner;                  // owner 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
    address[3] public admins;              // customers EOA
    uint256 public balance;                // balance
    uint256 public pendingBalance;         // balance from Pending Transactions
    mapping(uint=>Product) public products;// products
    Transaction[] public acceptedTransactions;
    Transaction[] public declinedTransactions;
    Transaction[] public clientDeclinedTransactions;

    // ERC-20 Token properties
    string public name = "MyShopToken";
    string public symbol = "MST";
    uint256 public decimals = 18;
    uint256 public totalSupply_ = 1000000000000000000000000; // 1,000,000 + 18 decimals
    uint256 public ethereumExchangeRate = 60; // 1 wei = 60 MST
    mapping(address => uint256) balances;
    mapping(address => mapping (address => uint256)) allowed;

    // private
    address[] pendingTransaction;
    mapping(address=>address[]) answeredTransactions;
    mapping(address => bool) adminExists;
    mapping(address => uint) adminIdx;
    mapping(address => Transaction) transactionMap;
    AdminAccountChange public adminAccountChange;

    // structs
    struct Transaction{
        uint productId;
        address from;
        uint amount;
        string state;
        uint accepted;
        uint rejected;
        bool exists;
        address[] answeredAdmins;
    }
    struct Product{
        string name;
        uint id;
        uint amount;
    }
    struct AdminAccountChange{
        address currentAccount;
        address newAccount;
        uint accept;
        uint decline;
        address[] answeredAdmins;
        bool exists;
    }

    constructor() {
        // initialize the owner and 3 admins
        owner = msg.sender;
        admins[0] = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
        adminExists[admins[0]] = true;
        adminIdx[admins[0]] = 0;

        admins[1] = 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db;
        adminExists[admins[1]] = true;
        adminIdx[admins[1]] = 1;

        admins[2] = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
        adminExists[admins[2]] = true;
        adminIdx[admins[2]] = 2;

        //initialize the products
        products[0] = Product("Pencil",0,500);
        products[1] = Product("Book",1,10000);
        products[2] = Product("Desk",2,100000);

        // On creation of the contract all the tokens go to the owner
        balances[msg.sender] = totalSupply_;
    }


    // return all the Pending Transactios
    function showPendingTransactions() public view returns(Transaction[] memory){
        Transaction[] memory t = new Transaction[](pendingTransaction.length);
        for(uint i=0; i<pendingTransaction.length; i++){
            t[i] = transactionMap[pendingTransaction[i]];
        }
        return (t);
    }
    // -- -- --
    // Transaction create accept decline
    function createTransaction(uint idProduct) public payable { // returns (uint256)

        balances[msg.sender] += msg.value*ethereumExchangeRate;

        // check if the product exists
        require(keccak256(bytes(products[idProduct].name)) != keccak256(bytes("")),"Product not found");

        // check if the amount is bigger than the product amount
        require(balances[msg.sender] >= products[idProduct].amount, "Your current ballance is smaller from the price of the product");

        // check if the transaction exists
        require(!transactionMap[msg.sender].exists, "You have allready a pending transaction, decline the old one first");


        // save the transaction as pending
        pendingBalance += products[idProduct].amount;
        balances[msg.sender] -= products[idProduct].amount;

        // save the Transaction
        pendingTransaction.push(msg.sender);
        address[] memory a;
        transactionMap[msg.sender] = Transaction(
            idProduct, 
            msg.sender, 
            products[idProduct].amount, 
            PENDING_REQ, 
            0, 
            0, 
            true, 
            a
        );
        emit E(products[idProduct].amount);

    }

    function acceptTransaction(address clientAddress) public returns(string memory){
        // check if he is admin
        require(adminExists[msg.sender], "You must be admin to accept this Transaction");
        // check if the transaction exists
        require(transactionMap[clientAddress].exists, "This Transaction doenst exist");
        // check if the transaction pending
        require(keccak256(bytes(transactionMap[clientAddress].state))==keccak256(bytes(PENDING_REQ)), "This Transaction isn't pending");

        // check if the admin is aswered allready
        address[] storage answered = transactionMap[clientAddress].answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this transaction");
        }
        // push the
        answered.push(msg.sender);
        transactionMap[clientAddress].answeredAdmins = answered;
        transactionMap[clientAddress].accepted+=1;

        if(transactionMap[clientAddress].accepted > 1){
            // make the Transaction accepted
            transactionMap[clientAddress].state = ACCEPT_REQ;

            // find the index of the address in the pendingTransaction array and delete it
            for(uint i=0; i<pendingTransaction.length;i++){
                if(pendingTransaction[i] == clientAddress){
                    // delete Pending Transactions
                    pendingTransaction = deletePendingTransaction(i);
                    // add to contract the amount of accepted Transaction
                    balance+=transactionMap[clientAddress].amount;
                    pendingBalance-=transactionMap[clientAddress].amount;
                    acceptedTransactions.push(transactionMap[clientAddress]);
                    delete transactionMap[msg.sender];
                    break;
                }
            }
            return "The Transaction is accepted";
        }

        return "The Transaction still Pending";
    }
    function declineYourTransaction() public returns(string memory){
        // check if the transaction exists
        require(transactionMap[msg.sender].exists, "You dont have any Transactions");
        // check if the transaction pending
        require(keccak256(bytes(transactionMap[msg.sender].state))==keccak256(bytes(PENDING_REQ)), "Your Transaction isn't pending");

        // make the Transaction declined
        transactionMap[msg.sender].state = CLIENT_DECLINE_REQ;

        // find the index of the address in the pendingTransaction array and delete it
        for(uint i=0; i<pendingTransaction.length;i++){
            if(pendingTransaction[i] == msg.sender){
                pendingTransaction = deletePendingTransaction(i);
                pendingBalance -= transactionMap[msg.sender].amount;
                clientDeclinedTransactions.push(transactionMap[msg.sender]);
                //return the amount cost of the product
                //(payable (msg.sender)).transfer(transactionMap[msg.sender].amount);
                balances[msg.sender] += transactionMap[msg.sender].amount;
                delete transactionMap[msg.sender];
                return "Your Transaction declined successfully";
            }
        }

        return "Something Happened";
    }
    function declineTransaction(address payable clientAddress) public returns(string memory){
        // check if he is admin
        require(adminExists[msg.sender], "You must be admin to accept this Transaction");
        // check if the transaction exists
        require(transactionMap[clientAddress].exists, "This Transaction doenst exist");
        // check if the transaction pending
        require(keccak256(bytes(transactionMap[clientAddress].state))==keccak256(bytes(PENDING_REQ)), "This Transaction isn't pending");

        // check if the admin is aswered allready
        address[] storage answered = transactionMap[clientAddress].answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this transaction");
        }
        // push the
        answered.push(msg.sender);
        transactionMap[clientAddress].answeredAdmins = answered;
        transactionMap[clientAddress].rejected+=1;

        if(transactionMap[clientAddress].rejected > 1){
            // make the Transaction declined
            transactionMap[clientAddress].state = DECLINE_REQ;


            // find the index of the address in the pendingTransaction array and delete it
            for(uint i=0; i<pendingTransaction.length;i++){
                if(pendingTransaction[i] == clientAddress){
                    pendingTransaction = deletePendingTransaction(i);
                    pendingBalance -= transactionMap[clientAddress].amount;
                    declinedTransactions.push(transactionMap[clientAddress]);
                    //clientAddress.transfer(transactionMap[clientAddress].amount);
                    balances[clientAddress] += transactionMap[msg.sender].amount;
                    delete transactionMap[clientAddress];
                    break;
                }
            }
            return "The Transaction is declined and the amount of the product is returned to the client";
        }
        return "The Transaction still Pending";
    }
    // -- -- --

    // -- -- --
    // Admin Account Change
    function changeAdminAccount(address newAddress) public returns(string memory){
        // chech if he is customer
        require(adminExists[msg.sender], "You must be admin to change the account");
        // check if accound change pending
        require(adminAccountChange.exists == false, "Account change is pending for another admin");
        //check if the newAddress is same whith msg.sender
        require(msg.sender != newAddress, "You address is same with the newAddress");
        // check if the new address exists
        require(!adminExists[newAddress], "This account is allready exists");
        address[] memory answeredAdmins;
        adminAccountChange = AdminAccountChange(msg.sender, newAddress, 1, 0, answeredAdmins, true);

        return("Change Account Pending");
    }
    function acceptAccountChange() public returns(string memory){
        // chech if he is customer
        require(adminExists[msg.sender], "You must be admin to change the account");
        // check if accound change pending
        require(adminAccountChange.exists == true, "Account change is not pending for another admin");
        // chech if he is the one who want to change his account
        require(adminAccountChange.currentAccount != msg.sender, "You cannot accept your request for Account Change");
        // check if the admin is aswered allready
        address[] storage answered = adminAccountChange.answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this transaction");
        }
        // record admin accept
        answered.push(msg.sender);
        adminAccountChange.answeredAdmins = answered;
        adminAccountChange.accept += 1;
        if(adminAccountChange.accept > 1){
            // change the his address
            admins[adminIdx[adminAccountChange.currentAccount]] = adminAccountChange.newAccount;
            // update exists map
            adminExists[adminAccountChange.newAccount] = true;
            //update idx map
            adminIdx[adminAccountChange.newAccount] = adminIdx[adminAccountChange.currentAccount];
            //delete
            adminIdx[adminAccountChange.currentAccount] = 0;
            adminExists[adminAccountChange.currentAccount] = false;
            delete adminAccountChange;
            return "Account Change accepted";
        }
        return "";
    }
    function declineAccountChange() public returns(string memory){
        // chech if he is customer
        require(adminExists[msg.sender], "You must be admin to change the account");
        // check if accound change pending
        require(adminAccountChange.exists == true, "Account change is not pending for another admin");
        // chech if he is the one who want to change his account
        require(adminAccountChange.currentAccount != msg.sender, "You cannot decline your request for Account Change");
        // check if the admin is aswered allready
        address[] storage answered = adminAccountChange.answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this transaction");
        }
        // record admin accept
        answered.push(msg.sender);
        adminAccountChange.answeredAdmins = answered;
        adminAccountChange.decline += 1;
        if(adminAccountChange.decline > 1){
            delete adminAccountChange;
            return "Account Change decline";
        }
        return "";
    }
    // -- -- --

    function destroy() private{
        selfdestruct(payable(owner));
    }
    // -- -- --
    // Get value and data from the client
    // called when we have no data
    receive() payable external{
        balances[msg.sender] += msg.value*ethereumExchangeRate;
    }
    
    
    // -- -- --

    //encode the id of the product for the abs
    function encodeIdProduct(uint id) public pure returns (bytes memory, string memory) {
        return (abi.encode(id), "Add this hex to the transact Input, is the id of your product");
    }
    // Move the last element to the deleted spot.
    // Remove the last element.
    function deletePendingTransaction(uint index) internal returns(address[] storage) {
        require(index < pendingTransaction.length);
        pendingTransaction[index] = pendingTransaction[pendingTransaction.length-1];
        pendingTransaction.pop();
        return pendingTransaction;
    }
    function test() public returns(uint) {
        answeredTransactions[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4].push(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db);
        answeredTransactions[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4].push(0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB);
        address[] memory a = answeredTransactions[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4];
        answeredTransactions[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4] = a;
        return answeredTransactions[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4].length;
    }


    /*
        ERC-20 Token methods
    */
    function totalSupply() public override view returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return balances[tokenOwner];
    }

    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-numTokens;
        balances[receiver] = balances[receiver]+numTokens;
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address spender, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][spender] = numTokens;
        emit Approval(msg.sender, spender, numTokens);
        return true;
    }

    function allowance(address _owner, address spender) public override view returns (uint) {
        return allowed[_owner][spender];
    }

    function transferFrom(address _owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[_owner], "The owner does't have enough tokens.");
        require(numTokens <= allowed[_owner][msg.sender], "You are not allowed to transfer that amount.");

        balances[_owner] = balances[_owner]-numTokens;
        allowed[_owner][msg.sender] = allowed[_owner][msg.sender]-numTokens;
        balances[buyer] = balances[buyer]+numTokens;
        emit Transfer(_owner, buyer, numTokens);
        return true;
    }

    function changeEthereumExchangeRate(uint256 newExchangeRate) public{
        // check if he is an admin
        require(adminExists[msg.sender], "You must be admin to change the account");
        ethereumExchangeRate = newExchangeRate;
    }

}
