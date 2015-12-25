//
//  ChatViewController.swift
//  Example
//
//  Created by CrazyWisdom on 15/12/24.
//  Copyright © 2015年 emqtt.io. All rights reserved.
//

import UIKit

class ChatViewController: UIViewController {

    @IBOutlet weak var messageTextView: UITextView! {
        didSet {
            //messageTextView.scrollEnabled = false
            messageTextView.layer.cornerRadius = 5
        }
    }
    
    @IBOutlet weak var messageTextViewHeightConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        messageTextView.delegate = self
    }
        

}


extension ChatViewController: UITextViewDelegate {
    
    func textViewDidChange(textView: UITextView) {
        if textView.contentSize.height != textView.frame.size.height {
            messageTextViewHeightConstraint.constant = textView.contentSize.height
            textView.layoutIfNeeded()
        }
    }
}