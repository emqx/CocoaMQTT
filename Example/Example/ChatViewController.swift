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
        }
    }
    var mqtt: CocoaMQTT?
    var messages: [String] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var messageTextView: UITextView! {
        didSet {
            messageTextView.layer.cornerRadius = 5
        }
    }
    @IBOutlet weak var animalAvatarImageView: UIImageView!
    
    @IBOutlet weak var messageTextViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var sendMessageButton: UIButton! {
        didSet {
            sendMessageButton.enabled = false
        }
    }
    
    @IBAction func sendMessage() {
        let message = messageTextView.text
        //messages.append(message)
        mqtt!.publish("/a/b/c", withString: message, qos: .QOS1, retain: true)
       
        messageTextView.text = ""
        sendMessageButton.enabled = false
        messageTextViewHeightConstraint.constant = messageTextView.contentSize.height
        messageTextView.layoutIfNeeded()
    }
    @IBAction func disconnect() {
        mqtt!.disconnect()
        //dismissViewControllerAnimated(true, completion: nil)
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
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "receivedMessage:", name: "MQTTMessageNotification", object: nil)
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    
    func receivedMessage(notification: NSNotification) {
        let userInfo = notification.userInfo as! [String: AnyObject]
        let message = userInfo["message"] as! String
        messages.append(message)
    }

}


extension ChatViewController: UITextViewDelegate {
    
    func textViewDidChange(textView: UITextView) {
        if textView.contentSize.height != textView.frame.size.height {
            messageTextViewHeightConstraint.constant = textView.contentSize.height
            textView.layoutIfNeeded()
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
        let cell = tableView.dequeueReusableCellWithIdentifier("leftMessageCell", forIndexPath: indexPath) as! ChatLeftMessageCell
        cell.contentLabel.text = messages[indexPath.row]
        return cell
    }
}

