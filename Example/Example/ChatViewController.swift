//
//  ChatViewController.swift
//  Example
//
//  Created by CrazyWisdom on 15/12/24.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import UIKit
import CocoaMQTT


class ChatViewController: UIViewController {
    var animal: String? {
        didSet {
            animalAvatarImageView.image = UIImage(named: animal!)
            if let animal = animal {
                switch animal {
                case "Sheep":
                    sloganLabel.text = "Four legs good, two legs bad."
                case "Pig":
                    sloganLabel.text = "All animals are equal."
                case "Horse":
                    sloganLabel.text = "I will work harder."
                default:
                    break
                }
            }
        }
    }
    var mqtt: CocoaMQTT?
    var messages: [ChatMessage] = [] {
        didSet {
            tableView.reloadData()
            scrollToBottom()
        }
    }
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var messageTextView: UITextView! {
        didSet {
            messageTextView.layer.cornerRadius = 5
        }
    }
    @IBOutlet weak var animalAvatarImageView: UIImageView!
    @IBOutlet weak var sloganLabel: UILabel!
    
    @IBOutlet weak var messageTextViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var inputViewBottomConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var sendMessageButton: UIButton! {
        didSet {
            sendMessageButton.enabled = false
        }
    }
    
    @IBAction func sendMessage() {
        let message = messageTextView.text
        if let client = animal {
            mqtt!.publish("chat/room/animals/client/" + client, withString: message, qos: .QOS1)
        }
    
        messageTextView.text = ""
        sendMessageButton.enabled = false
        messageTextViewHeightConstraint.constant = messageTextView.contentSize.height
        messageTextView.layoutIfNeeded()
        view.endEditing(true)
    }
    @IBAction func disconnect() {
        mqtt!.disconnect()
        navigationController?.popViewControllerAnimated(true)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.hidden = true
        animal = tabBarController?.selectedViewController?.tabBarItem.title
        automaticallyAdjustsScrollViewInsets = false
        messageTextView.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 50
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.receivedMessage(_:)), name: "MQTTMessageNotification" + animal!, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.keyboardChanged(_:)), name: UIKeyboardWillChangeFrameNotification, object: nil)
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    
    func keyboardChanged(notification: NSNotification) {
        let userInfo = notification.userInfo as! [String: AnyObject]
        let keyboardValue = userInfo["UIKeyboardFrameEndUserInfoKey"]
        let bottomDistance = UIScreen.mainScreen().bounds.size.height - (navigationController?.navigationBar.frame.height)! - keyboardValue!.CGRectValue.origin.y
        
        if bottomDistance > 0 {
            inputViewBottomConstraint.constant = bottomDistance
        } else {
            inputViewBottomConstraint.constant = 0
        }
        view.layoutIfNeeded()
    }

    func receivedMessage(notification: NSNotification) {
        let userInfo = notification.userInfo as! [String: AnyObject]
        let content = userInfo["message"] as! String
        let topic = userInfo["topic"] as! String
        let sender = topic.stringByReplacingOccurrencesOfString("chat/room/animals/client/", withString: "")
        let chatMessage = ChatMessage(sender: sender, content: content)
        messages.append(chatMessage)
    }

    func scrollToBottom() {
        let count = messages.count
        if count > 3 {
            let indexPath = NSIndexPath(forRow: count - 1, inSection: 0)
            tableView.scrollToRowAtIndexPath(indexPath, atScrollPosition: .Bottom, animated: true)
        }
    }
}


extension ChatViewController: UITextViewDelegate {
    
    func textViewDidChange(textView: UITextView) {
        if textView.contentSize.height != textView.frame.size.height {
            let textViewHeight = textView.contentSize.height
            if textViewHeight < 100 {
                messageTextViewHeightConstraint.constant = textViewHeight
                textView.layoutIfNeeded()
            }
        }
        
        if textView.text == "" {
            sendMessageButton.enabled = false
        } else {
            sendMessageButton.enabled = true
        }
    }
    
}

extension ChatViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        if message.sender == animal {
            let cell = tableView.dequeueReusableCellWithIdentifier("rightMessageCell", forIndexPath: indexPath) as! ChatRightMessageCell
            cell.contentLabel.text = messages[indexPath.row].content
            cell.avatarImageView.image = UIImage(named: animal!)
            return cell
        } else {
            let cell = tableView.dequeueReusableCellWithIdentifier("leftMessageCell", forIndexPath: indexPath) as! ChatLeftMessageCell
            cell.contentLabel.text = messages[indexPath.row].content
            cell.avatarImageView.image = UIImage(named: message.sender)
            return cell
        }
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        view.endEditing(true)
    }
}
