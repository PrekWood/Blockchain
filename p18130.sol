// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;
import "hardhat/console.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract UnipiContract is IERC20 { 

    address payable owner;
    address payable store;
    mapping (address => bool) admins;
    AdminChangeState adminChangeState;
    Order[] orders;
    uint256 balance;
    uint256 pendingBalance;
    WithdrawRequest[] withdrawRequests;

    // ERC-20 Token properties
    string name = "UnipiToken";
    string symbol = "UT";
    uint256 decimals = 18;
    uint256 totalTokenSupply = 1000000000000000000000000; 
    uint256 ethereumExchangeRate = 90; // 1 wei = 90 UnipiTokens
    mapping(address => uint256) userBalances;
    mapping(address => mapping (address => uint256)) accountsWithAccess;

    struct AdminChangeState{
        bool exists; 
        address oldAdmin;
        address newAdmin;
    }
    struct Order{
        uint256 id;
        uint256 amount;
        address customer;
        OrderState state;
        bool exists; 
    }
    enum OrderState {
        PENDING, 
        COMPLETED,
        CANCELED 
    }
    struct WithdrawRequest{
        bool exists; 
        uint256 id;
        address to;
        uint256 amount;
        address[] adminsApproved;
    }

    constructor() {
        owner = payable(msg.sender);

        admins[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4] = true;
        admins[0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db] = true;
        admins[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2] = true;

        store = payable(0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB);

        userBalances[owner] = totalTokenSupply;
    }
    function destroy() public onlyAdmin{
        selfdestruct(owner);
    }

    modifier onlyAdmin(){
        require(admins[msg.sender], "You're not an admin");
        _;
    }

    // Admin Change
    function adminChange(address newAdminAddress) public onlyAdmin {
        require(!adminChangeState.exists, "Another admin change is currently running.");
        adminChangeState = AdminChangeState(true, msg.sender, newAdminAddress);
    }
    function adminChangeApprove() public onlyAdmin{
        require(msg.sender != adminChangeState.oldAdmin, "You cannot approve your own account change.");

        admins[adminChangeState.oldAdmin] = false;
        admins[adminChangeState.newAdmin] = true;
        adminChangeState.exists = false;
    }
    function adminChangeDecline() public onlyAdmin{
        adminChangeState.exists = false;
    }

    // Order 
    function orderCreate(uint idOrder, uint256 amount) public {

        require(userBalances[msg.sender] >= amount, "Your balance is not enough to pay the order");

        // Search if idOrder is unique
        Order memory order;
        for(uint orderIndex = 0; orderIndex < orders.length; orderIndex++){
            if(orders[orderIndex].id == idOrder){
                order = orders[orderIndex];
                break;
            }
        }
        require(!order.exists, "The idOrder is not unique");

        // Reserve the tokens
        userBalances[msg.sender] -= amount;
        pendingBalance += amount;

        // Crate order
        orders.push(
            Order(
                idOrder,
                amount,
                msg.sender, 
                OrderState.PENDING, 
                true
            )
        );
    }
    function orderApprove(uint idOrder) public {
        require(msg.sender == store, "You don't have authority to approve orders");

        // Search for order
        Order memory order;
        for(uint orderIndex = 0; orderIndex < orders.length; orderIndex++){
            if(orders[orderIndex].id == idOrder){
                order = orders[orderIndex];
                break;
            }
        }
        require(order.exists, "Could not find an order with this id");

        order.state = OrderState.COMPLETED;
        pendingBalance -= order.amount;
        balance += order.amount;
    }
    function orderDecline(uint idOrder) public { 
        // Search for order
        Order memory order;
        for(uint orderIndex = 0; orderIndex < orders.length; orderIndex++){
            if(orders[orderIndex].id == idOrder){
                order = orders[orderIndex];
                break;
            }
        }
        require(order.exists, "Could not find an order with this id");

        // Only grant access to the store or the customer
        require(msg.sender == store || msg.sender == order.customer, "You don't have authority to approve orders");
        require(order.state == OrderState.PENDING, "The order is either canceled or completed");

        order.state = OrderState.CANCELED;
        pendingBalance -= order.amount;
        userBalances[order.customer] += order.amount;
    }

    // Withdrawals
    function withdraw(uint256 tokenAmount) public returns (uint256 idWithdrawRequest){ 
        require(tokenAmount <= balance, "The contract currently does not have the number of tokens you want to withdraw.");

        uint256 id = withdrawRequests.length + 1;
        address[] memory emptyAddressArray;
        withdrawRequests.push(
            WithdrawRequest(
                true,
                id,
                msg.sender,
                tokenAmount,
                emptyAddressArray
            )
        );

        return id;
    }
    function withdrawAccept(uint256 idWithdrawRequest) public onlyAdmin returns(string memory)  { 
        // Search for request
        WithdrawRequest memory request;
        uint requestPosition;
        for(uint requestIndex = 0; requestIndex < withdrawRequests.length; requestIndex++){
            if(withdrawRequests[requestIndex].id == idWithdrawRequest){
                request = withdrawRequests[requestIndex];
                requestPosition = requestIndex;
                break;
            }
        }
        require(request.exists, "Could not find a withdrawal request with this id");

        // Check if already approved
        bool alreadyApproved = false;
        for(uint adminIndex = 0; adminIndex < request.adminsApproved.length; adminIndex++){
            if(request.adminsApproved[adminIndex] == msg.sender){
                alreadyApproved = true;
                break;
            }
        }
        require(!alreadyApproved, "You have already approved this withdrawal");

        withdrawRequests[requestPosition].adminsApproved.push(msg.sender);

        if(request.adminsApproved.length >= 1){
            require(request.amount <= balance, "The amount is not available right now.");
            
            // Transfer the amount
            uint etherAmount = uint(request.amount)/uint(ethereumExchangeRate);
            payable(request.to).transfer(etherAmount);

            // Delete withdraw request
            delete withdrawRequests[requestPosition];

            return "Withdrawal completed";
        }else{
            return "Another one approve is needed to complete the withdrawal";
        }
    }
    function withdrawDecline(uint256 idWithdrawRequest) public onlyAdmin{ 
        // Search for request
        WithdrawRequest memory request;
        uint requestPosition;
        for(uint requestIndex = 0; requestIndex < withdrawRequests.length; requestIndex++){
            if(withdrawRequests[requestIndex].id == idWithdrawRequest){
                request = withdrawRequests[requestIndex];
                requestPosition = requestIndex;
                break;
            }
        }
        require(request.exists, "Could not find a withdrawal request with this id");

        // Delete withdraw request
        delete withdrawRequests[requestPosition];
    }


    // Change UnipiToken exchage rate
    function changeUnipiTokenExchangeRate(uint256 newExchangeRate) public{
        require(msg.sender == store, "You don't have authority to change the exchange rate");
        ethereumExchangeRate = newExchangeRate;
    }
    function buyUnipiTokens() public payable{
        userBalances[msg.sender] += msg.value*ethereumExchangeRate;
    }

    /*
        ERC-20 Token methods
    */
    function totalSupply() public override view returns (uint256) {
        return totalTokenSupply;
    }

    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return userBalances[tokenOwner];
    }

    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= userBalances[msg.sender]);
        userBalances[msg.sender] = userBalances[msg.sender]-numTokens;
        userBalances[receiver] = userBalances[receiver]+numTokens;
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address spender, uint256 numTokens) public override returns (bool) {
        accountsWithAccess[msg.sender][spender] = numTokens;
        emit Approval(msg.sender, spender, numTokens);
        return true;
    }

    function allowance(address _owner, address spender) public override view returns (uint) {
        return accountsWithAccess[_owner][spender];
    }

    function transferFrom(address _owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= userBalances[_owner]);
        require(numTokens <= accountsWithAccess[_owner][msg.sender]);

        userBalances[_owner] = userBalances[_owner]-numTokens;
        accountsWithAccess[_owner][msg.sender] = accountsWithAccess[_owner][msg.sender]-numTokens;
        userBalances[buyer] = userBalances[buyer]+numTokens;
        emit Transfer(_owner, buyer, numTokens);
        return true;
    }

}
