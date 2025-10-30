// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Crypto-Based Food Delivery Payments
 * @dev Smart contract for managing food delivery orders with cryptocurrency payments
 */
contract Project {
    
    // Struct to represent a food order
    struct Order {
        uint256 orderId;
        address customer;
        address restaurant;
        address deliveryPartner;
        uint256 amount;
        uint256 deliveryFee;
        uint256 platformFee;
        OrderStatus status;
        uint256 timestamp;
    }
    
    // Enum for order status
    enum OrderStatus {
        Pending,
        Confirmed,
        Preparing,
        OutForDelivery,
        Delivered,
        Cancelled,
        Disputed
    }
    
    // State variables
    address public platformOwner;
    uint256 public platformFeePercentage;
    uint256 public orderCounter;
    
    // Mappings
    mapping(uint256 => Order) public orders;
    mapping(address => uint256) public restaurantBalances;
    mapping(address => uint256) public deliveryPartnerBalances;
    mapping(address => bool) public registeredRestaurants;
    mapping(address => bool) public registeredDeliveryPartners;
    
    // Events
    event OrderPlaced(uint256 indexed orderId, address indexed customer, address indexed restaurant, uint256 amount);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
    event PaymentReleased(uint256 indexed orderId, address indexed restaurant, address indexed deliveryPartner);
    event RestaurantRegistered(address indexed restaurant);
    event DeliveryPartnerRegistered(address indexed partner);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    
    // Modifiers
    modifier onlyPlatformOwner() {
        require(msg.sender == platformOwner, "Only platform owner can call this");
        _;
    }
    
    modifier onlyCustomer(uint256 _orderId) {
        require(orders[_orderId].customer == msg.sender, "Only customer can call this");
        _;
    }
    
    modifier onlyRestaurant(uint256 _orderId) {
        require(orders[_orderId].restaurant == msg.sender, "Only restaurant can call this");
        _;
    }
    
    modifier onlyDeliveryPartner(uint256 _orderId) {
        require(orders[_orderId].deliveryPartner == msg.sender, "Only delivery partner can call this");
        _;
    }
    
    constructor(uint256 _platformFeePercentage) {
        platformOwner = msg.sender;
        platformFeePercentage = _platformFeePercentage;
        orderCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Place Order
     * @notice Customer places a food order and sends payment
     * @param _restaurant Address of the restaurant
     * @param _deliveryPartner Address of the delivery partner
     * @param _deliveryFee Delivery fee amount
     */
    function placeOrder(
        address _restaurant,
        address _deliveryPartner,
        uint256 _deliveryFee
    ) external payable returns (uint256) {
        require(msg.value > _deliveryFee, "Payment must be greater than delivery fee");
        require(registeredRestaurants[_restaurant], "Restaurant not registered");
        require(registeredDeliveryPartners[_deliveryPartner], "Delivery partner not registered");
        
        orderCounter++;
        uint256 foodAmount = msg.value - _deliveryFee;
        uint256 platformFee = (foodAmount * platformFeePercentage) / 100;
        
        orders[orderCounter] = Order({
            orderId: orderCounter,
            customer: msg.sender,
            restaurant: _restaurant,
            deliveryPartner: _deliveryPartner,
            amount: foodAmount - platformFee,
            deliveryFee: _deliveryFee,
            platformFee: platformFee,
            status: OrderStatus.Pending,
            timestamp: block.timestamp
        });
        
        emit OrderPlaced(orderCounter, msg.sender, _restaurant, foodAmount);
        
        return orderCounter;
    }
    
    /**
     * @dev Core Function 2: Update Order Status
     * @notice Updates the status of an order through the delivery lifecycle
     * @param _orderId Order ID
     * @param _status New status
     */
    function updateOrderStatus(uint256 _orderId, OrderStatus _status) external {
        require(_orderId > 0 && _orderId <= orderCounter, "Invalid order ID");
        Order storage order = orders[_orderId];
        
        if (_status == OrderStatus.Confirmed || _status == OrderStatus.Preparing) {
            require(msg.sender == order.restaurant, "Only restaurant can confirm/prepare");
        } else if (_status == OrderStatus.OutForDelivery) {
            require(msg.sender == order.deliveryPartner, "Only delivery partner can update");
        } else if (_status == OrderStatus.Delivered) {
            require(msg.sender == order.deliveryPartner, "Only delivery partner can mark delivered");
            _releasePayment(_orderId);
        } else if (_status == OrderStatus.Cancelled) {
            require(
                msg.sender == order.customer || 
                msg.sender == order.restaurant || 
                msg.sender == platformOwner,
                "Unauthorized to cancel"
            );
            _refundCustomer(_orderId);
        }
        
        order.status = _status;
        emit OrderStatusUpdated(_orderId, _status);
    }
    
    /**
     * @dev Core Function 3: Withdraw Earnings
     * @notice Allows restaurants and delivery partners to withdraw their earnings
     */
    function withdrawEarnings() external {
        uint256 amount = 0;
        
        if (registeredRestaurants[msg.sender]) {
            amount = restaurantBalances[msg.sender];
            require(amount > 0, "No balance to withdraw");
            restaurantBalances[msg.sender] = 0;
        } else if (registeredDeliveryPartners[msg.sender]) {
            amount = deliveryPartnerBalances[msg.sender];
            require(amount > 0, "No balance to withdraw");
            deliveryPartnerBalances[msg.sender] = 0;
        } else {
            revert("Not a registered participant");
        }
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FundsWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Internal function to release payment after successful delivery
     */
    function _releasePayment(uint256 _orderId) internal {
        Order storage order = orders[_orderId];
        
        restaurantBalances[order.restaurant] += order.amount;
        deliveryPartnerBalances[order.deliveryPartner] += order.deliveryFee;
        
        emit PaymentReleased(_orderId, order.restaurant, order.deliveryPartner);
    }
    
    /**
     * @dev Internal function to refund customer on cancellation
     */
    function _refundCustomer(uint256 _orderId) internal {
        Order storage order = orders[_orderId];
        
        uint256 refundAmount = order.amount + order.deliveryFee + order.platformFee;
        
        (bool success, ) = payable(order.customer).call{value: refundAmount}("");
        require(success, "Refund failed");
    }
    
    /**
     * @dev Register a restaurant on the platform
     */
    function registerRestaurant(address _restaurant) external onlyPlatformOwner {
        registeredRestaurants[_restaurant] = true;
        emit RestaurantRegistered(_restaurant);
    }
    
    /**
     * @dev Register a delivery partner on the platform
     */
    function registerDeliveryPartner(address _partner) external onlyPlatformOwner {
        registeredDeliveryPartners[_partner] = true;
        emit DeliveryPartnerRegistered(_partner);
    }
    
    /**
     * @dev Get order details
     */
    function getOrderDetails(uint256 _orderId) external view returns (Order memory) {
        require(_orderId > 0 && _orderId <= orderCounter, "Invalid order ID");
        return orders[_orderId];
    }
    
    /**
     * @dev Platform owner can withdraw collected platform fees
     */
    function withdrawPlatformFees() external onlyPlatformOwner {
        uint256 balance = address(this).balance;
        
        // Calculate total locked funds
        uint256 lockedFunds = 0;
        for (uint256 i = 1; i <= orderCounter; i++) {
            if (orders[i].status != OrderStatus.Delivered && 
                orders[i].status != OrderStatus.Cancelled) {
                lockedFunds += orders[i].amount + orders[i].deliveryFee + orders[i].platformFee;
            }
        }
        
        uint256 withdrawable = balance - lockedFunds;
        require(withdrawable > 0, "No fees to withdraw");
        
        (bool success, ) = payable(platformOwner).call{value: withdrawable}("");
        require(success, "Transfer failed");
    }
}







