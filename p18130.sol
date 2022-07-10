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
    mapping (address => bool) admins;
    AdminChangeState adminChangeState;
    mapping (uint => Product) products;
    mapping (address => Order) orders;
    uint256 balance;
    uint256 pendingBalance;

    // ERC-20 Token properties
    string name = "UnipiToken";
    string symbol = "UT";
    uint256 decimals = 18;
    uint256 totalTokenSupply = 1000000000000000000000000;
    uint256 ethereumExchangeRate = 90; // 1 wei = 90 MST
    mapping(address => uint256) userBalances;
    mapping(address => mapping (address => uint256)) accountsWithAccess;

    struct Product{
        uint id;
        string name;
        uint price;
        bool exists;
    }
    struct AdminChangeState{
        bool exists;
        address oldAdmin;
        address newAdmin;
    }
    struct Order{
        address customer;
        uint idProduct;
        OrderState state;
        bool exists;
        address[] approvedAdmins;
    }
    enum OrderState { PENDING, COMPLETED, CANCELED }

    constructor() {
        owner = payable(msg.sender);
        admins[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4] = true;
        admins[0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db] = true;
        admins[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2] = true;

        products[0] = Product(1,"Product #1", 700, true);
        products[1] = Product(2,"Product #2", 10000, true);
        products[2] = Product(3,"Product #3", 200000, true);

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

        adminChangeState.exists = true;
        adminChangeState.oldAdmin = msg.sender;
        adminChangeState.newAdmin = newAdminAddress;
        adminChangeState.exists = true;
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

    // Client
    function orderCreate(uint idProduct) payable public {
        require(products[idProduct].exists, "Invalid id product");

        // Add ETH of the request to the user balance
        uint256 unipiTokenValue = msg.value*ethereumExchangeRate;
        userBalances[msg.sender] += unipiTokenValue;

        // Check if balance is enough
        require(userBalances[msg.sender] >= products[idProduct].price, "Your balance is not enough to buy the product");

        // Reserve the tokens
        userBalances[msg.sender] -= products[idProduct].price;
        pendingBalance += products[idProduct].price;

        // Crate order
        address[] memory emptyAddressArray;
        orders[msg.sender] = Order(
            msg.sender,
            idProduct,
            OrderState.PENDING,
            true,
            emptyAddressArray
        );
    }
    function orderApprove(address customerAddress) public onlyAdmin{
        require(orders[customerAddress].exists, "The customer hasn't made any orders yet");
        require(customerAddress != msg.sender, "You cannot approve your own order");

        // Check if already approved
        address[] storage approvedAdmins = orders[customerAddress].approvedAdmins;
        for(uint approvedAdminIndex=0; approvedAdminIndex < approvedAdmins.length; approvedAdminIndex++){
            require(approvedAdmins[approvedAdminIndex] != msg.sender, "You have already approved this order");
        }
        orders[customerAddress].approvedAdmins.push(msg.sender);

        if(orders[customerAddress].approvedAdmins.length >= 2){
            uint256 orderTotal  = products[orders[customerAddress].idProduct].price;
            pendingBalance -= orderTotal;
            balance += orderTotal;
            orders[customerAddress].state = OrderState.COMPLETED;
        }
    }
    function orderDecline(address customerAddress) public{
        require(admins[msg.sender] || msg.sender == customerAddress, "You dont have access editing the order");
        require(orders[customerAddress].exists, "The customer hasn't made any orders yet");
        require(orders[customerAddress].state == OrderState.PENDING, "The order cannot be canceled");

        // The orders value goes back to the clients balance
        uint256 orderTotal  = products[orders[customerAddress].idProduct].price;
        pendingBalance -= orderTotal;
        userBalances[customerAddress] += orderTotal;
        orders[customerAddress].state = OrderState.CANCELED;
    }


    function changeEthereumExchangeRate(uint256 newExchangeRate) public{
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