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
            sendMessageButton.isEnabled = false
        }
    }
    
    @IBAction func sendMessage() {
        let message = messageTextView.text
        if let client = animal {
            mqtt!.publish("chat/room/animals/client/" + client, withString: message!, qos: .qos1)
        }
        
        messageTextView.text = ""
        sendMessageButton.isEnabled = false
        messageTextViewHeightConstraint.constant = messageTextView.contentSize.height
        messageTextView.layoutIfNeeded()
        view.endEditing(true)
    }
    @IBAction func disconnect() {
        mqtt!.disconnect()
        _ = navigationController?.popViewController(animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.isHidden = true
        animal = tabBarController?.selectedViewController?.tabBarItem.title
        automaticallyAdjustsScrollViewInsets = false
        messageTextView.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 50
        
        let name = NSNotification.Name(rawValue: "MQTTMessageNotification" + animal!)
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.receivedMessage(notification:)), name: name, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.keyboardChanged(notification:)), name: NSNotification.Name.UIKeyboardWillChangeFrame, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func keyboardChanged(notification: NSNotification) {
        let userInfo = notification.userInfo as! [String: AnyObject]
        let keyboardValue = userInfo["UIKeyboardFrameEndUserInfoKey"]
        let bottomDistance = UIScreen.main.bounds.size.height - (navigationController?.navigationBar.frame.height)! - keyboardValue!.cgRectValue.origin.y
        
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
        let sender = topic.replacingOccurrences(of: "chat/room/animals/client/", with: "")
        let chatMessage = ChatMessage(sender: sender, content: content)
        messages.append(chatMessage)
    }
    
    func scrollToBottom() {
        let count = messages.count
        if count > 3 {
            let indexPath = IndexPath(row: count - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }
}


extension ChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if textView.contentSize.height != textView.frame.size.height {
            let textViewHeight = textView.contentSize.height
            if textViewHeight < 100 {
                messageTextViewHeightConstraint.constant = textViewHeight
                textView.layoutIfNeeded()
            }
        }
        
        if textView.text == "" {
            sendMessageButton.isEnabled = false
        } else {
            sendMessageButton.isEnabled = true
        }
    }
}

extension ChatViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        if message.sender == animal {
            let cell = tableView.dequeueReusableCell(withIdentifier: "rightMessageCell", for: indexPath) as! ChatRightMessageCell
            cell.contentLabel.text = messages[indexPath.row].content
            cell.avatarImageView.image = UIImage(named: animal!)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "leftMessageCell", for: indexPath) as! ChatLeftMessageCell
            cell.contentLabel.text = messages[indexPath.row].content
            cell.avatarImageView.image = UIImage(named: message.sender)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        view.endEditing(true)
    }
}
