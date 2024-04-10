// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

contract Market {
    IERC20 public erc20;
    IERC721 public erc721;

    bytes4 internal constant MAGIC_ON_ERC721_RECEIVED = 0x150b7a02;

    struct Order {
        address seller;
        uint256 tokenId;
        uint256 price;
    }

    //通过tokenId查询订单
    mapping(uint256 => Order) public orderOfId;

    //查询所有订单
    Order[] public orders;
    //通过TokenId查询相关订单，如果一个TokenId有多个订单怎么办？
    mapping(uint256 => uint256) public idToOrderIndex;

    //交易触发时间，保存日志
    //每次写操作都需要有一次事件
    event Deal(address seller, address buyer, uint256 tokenId, uint256 price);
    event NewOrder(address seller, uint256 tokenId, uint256 price);
    event PriceChanged(address seller, uint256 _tokenId, uint256 previousPrice, uint256 price);
    event OrderCancelled(address seller, uint256 tokenId);

    //初始化保存对应erc20和erc721的地址
    constructor(address _erc20, address _erc721) {
        //不允许0地址
        require(_erc20 != address(0), "zero address");
        require(_erc721 != address(0), "zero address");
        //TODO: 接口实例？
        erc20 = IERC20(_erc20);
        erc721 = IERC721(_erc721);
    }

    //通过通用代币（以太等）购买ERC721
    function buy(uint256 _tokenId) external {
        //直接通过TokenId寻找，代表这个订单已经有了
        address seller = orderOfId[_tokenId].seller;
        address buyer = msg.sender;
        uint256 price = orderOfId[_tokenId].price;

        require(erc20.transferFrom(buyer, seller, price), "transfer not successful");
        erc721.safeTransferFrom(address(this), buyer, _tokenId);

        //remove order(after selling)
        removeOrder(_tokenId);

        emit Deal(seller, buyer, _tokenId, price);
    }

    //取消订单
    function cancelOrder(uint256 _tokenId) external{
        address seller = orderOfId[_tokenId].seller;
        require(msg.sender == seller, "not seller");
        //solidity中的this是当前合约的地址
        //取消售卖，就发送回去
        erc721.safeTransferFrom(address(this), seller, _tokenId);
    }

    //修改价格
    function changePrice(uint256 _tokenId, uint256 _price) external {
        address seller = orderOfId[_tokenId].seller;
        require(msg.sender == seller, "not seller");

        uint256 previousPrice = orderOfId[_tokenId].price;
        orderOfId[_tokenId].price = _price;

        //需要修改所有和价值相关的地方,   sotorage关键字代表是存储引用类型的变量
        //storage才能修改链上数据
        Order storage order = orders[idToOrderIndex[_tokenId]];
        order.price = _price;

        //任务完成就释放事件
        emit PriceChanged(seller, _tokenId, previousPrice, _price);
    }

    //上架
    //自动调用合约的onErc721Received方法
    //首先要定义这个方法，合约双方是如何合作的
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data)  external returns (bytes4){
            uint256 price = toUint256(data, 0);
            require(price > 0, "price must be greater than 0" );
            //上架
            orders.push(Order(from, tokenId, price));
            orderOfId[tokenId] = Order(from, tokenId, price);
            idToOrderIndex[tokenId] = orders.length - 1;

            emit NewOrder(from, tokenId, price);
            return MAGIC_ON_ERC721_RECEIVED;
    }

    //进行格式转换
    function toUint256(bytes memory _bytes, uint256 _start) 
    public pure returns(uint256)
    {
        require(_start + 32 >= _start, "Market: toUint256_overflow");
        require(_bytes.length >= _start + 32, "Market: toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    //下架
    function  removeOrder(uint256 _tokenId) internal{
        uint256 index = idToOrderIndex[_tokenId];
        uint256 lastIndex = orders.length - 1;
        if (index != lastIndex) {
            //将原来位置的Order和OrderIndex都替换为最后一个
            Order storage lastOrder = orders[lastIndex];
            orders[index] = lastOrder;
            idToOrderIndex[lastOrder.tokenId] = index;
        }
        //删除最后一个
        orders.pop();
        //mapping可以直接delete
        delete orderOfId[_tokenId];
        delete idToOrderIndex[_tokenId];
        
    }
    
    function getOrderLength() external view returns(uint256) external view{
        returns (uint256) {
            return orders.length;
        }
    }

    function getAllNFTS() external view returns(orders[] memory) {
        return orders;
    }

    function getMyNFTs() external view returns(order[] memory) {
        Order[] memory myOrders = new Order[](orders.length);
        uint256 count = 0;
        for (uint256 i = 0; i < orders.length; i++) 
        {
            if (orders[i].seller == msg.sender) {
                myOrders[count] = orders[i];
                count++;
            }
        }
        return myOrders;
    }
}