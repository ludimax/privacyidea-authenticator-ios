//
//  PresenterQRParse.swift
//  privacyIDEA Authenticator
//
//  Created by Nils Behlen on 14.06.19.
//  Copyright © 2019 Nils Behlen. All rights reserved.
//

import Foundation
import SwiftOTP

extension Presenter: QRScanResultDelegate {
    func passScanResult(code: String) {
        // create a token from the scan result and add it to the list
        //U.log("scanned: \(code)")
        var type: String = Tokentype.HOTP
        var digits: Int = 6
        var algorithm: String = "sha1"
        var secret: Data = base32DecodeToData("ABCDEFGHIJKLMNOP")!
        var label: String = "Issuer:ID"
        var counter: Int = 1
        var period: Int? = nil
        var serial: String = ""
        var two_step_init = false
        var two_step_salt = 10              // default value in bytes, part that is generated by the phone
        var two_step_difficulty = 10000     // default value pbkdf2 iterations
        var two_step_output = 160           // default value output size of pbkdf in BIT
        
        var enrollment_credential:String = ""
        var enrollment_url:String = ""
        var expirationDate: Date = Date()
        var sslVerify: Bool = true
        var ttl: Int = 10
        var v: Int = 1 // push version
        
        var projNumber: String = ""
        var appID: String = ""
        var api_key: String = ""
        var projID: String = ""
        
        if let comp = URLComponents(string: code), let queryItems = comp.queryItems {
            
            if comp.host! == Tokentype.TOTP {
                type = Tokentype.TOTP
            } else if (comp.host! == Tokentype.PUSH) {
                type = Tokentype.PUSH
            }
            
            label = comp.path
            label.remove(at: label.startIndex) // remove first /
            serial = label
            for i in 0..<queryItems.count {
                switch queryItems[i].name {
                // MARK: DEFAULT KEY URI
                case "secret" :
                    guard let tmp = queryItems[i].value else {
                        U.log("failed for " + queryItems[i].name)
                        continue
                    }
                    secret = base32DecodeToData(tmp)!
                    break;
                case "issuer" :
                    guard let tmp = queryItems[i].value else {
                        U.log("failed for " + queryItems[i].name)
                        continue
                    }
                    let full_label = tmp + ":" + label
                    label = full_label
                    break;
                case "digits" :
                    guard let tmp = queryItems[i].value else {
                        U.log("failed for " + queryItems[i].name)
                        continue
                    }
                    digits = Int(tmp)!
                    break
                case "period" :
                    guard let tmp = queryItems[i].value else {
                        U.log("failed for " + queryItems[i].name)
                        continue
                    }
                    period = Int(tmp)
                    break
                case "counter" :
                    guard let tmp = queryItems[i].value else {
                        counter = 1
                        U.log("failed for " + queryItems[i].name)
                        continue
                    }
                    counter = Int(tmp)!
                    break
                case "algorithm" :
                    guard let tmp = queryItems[i].value else {
                        // use default on error / missing
                        continue
                    }
                    algorithm = tmp
                    break
                    ///////////////////////////////////////////////
                    // MARK: TWO STEP PARAMETERS
                // if at least one parameter is set, we start 2step init
                case "2step_salt" :
                    two_step_init = true
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    two_step_salt = Int(tmp)!
                    U.log("2step salt: \(two_step_salt)")
                    break
                case "2step_output" :
                    two_step_init = true
                    guard let tmp = queryItems[i].value else {
                        // if there is no value, we derive it from the tokens algorithm
                        if algorithm == "sha1" {
                        } // is already default
                        if algorithm == "sha256" {
                            two_step_output = 256
                        }
                        if algorithm == "sha512" {
                            two_step_output = 512
                        }
                        continue
                    }
                    two_step_output = Int(tmp)! * 8     // comes in byte, we need bit
                    U.log("2step output: \(two_step_output)")
                    break
                case "2step_difficulty" :
                    two_step_init = true
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    two_step_difficulty = Int(tmp)!
                    U.log("2step diff: \(two_step_difficulty)")
                    break
                    ///////////////////////////////////////////////
                    //     MARK:   PUSH PARAMETERS
                ///////////////////////////////////////////////
                case "enrollment_credential" :
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    enrollment_credential = tmp
                    break
                case "url":
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    enrollment_url = tmp
                    break
                case "ttl" :
                    if let tmp = queryItems[i].value {
                        ttl = Int(tmp)!
                    }
                    expirationDate = Date().addingTimeInterval(Double(ttl) * 60.0)
                    U.log("TTL is: \(expirationDate) and current is \(Date())")
                    break
                case "v":
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    v = Int(tmp)!
                    break
                case "sslVerify":
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    if Int(tmp)! == 0 {
                        sslVerify = false
                    }
                    break
                    
                case "serial":
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    serial = tmp
                    break;
                    ///////////////////////////////////////////////
                // MARK: FIREBASE PARAMETERS
                case "projectid" :
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    projID = tmp
                    break
                case "appidios" :
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    appID = tmp
                    break
                case "apikeyios" :
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    api_key = tmp
                    break
                case "projectnumber" :
                    guard let tmp = queryItems[i].value else {
                        continue
                    }
                    projNumber = tmp
                    break
                default:
                    break;
                }
            }
        }
        
        if type == Tokentype.HOTP || type == Tokentype.TOTP {
            let t = Token(type: type,label: label, serial: label, digits: digits, algorithm: algorithm, secret: secret,  counter: counter, period: period)
            // MARK: TWO STEP START
            if two_step_init {
                // sends registration to background queue
                DispatchQueue.global(qos: .background).async {
                    U.log("starting 2step")
                    let t2 = TwoStepRollout(self.tokenlistDelegate!)
                        .do2stepinit(t: t, salt_size: two_step_salt, difficulty: two_step_difficulty, output: two_step_output)
                    self.addToken(t2)
                }
            } else {
                self.addToken(t)
            }
        } else { // MARK: PUSH START
            if v > 1 {
                tokenlistDelegate?.showMessageWithOKButton(title: "Error", message: "Push version is higher than the one supported by this phone")
                return
            }
            
            let t = Token(type: Tokentype.PUSH, label: label, serial: serial, enrollment_credential: enrollment_credential, enrollment_url: enrollment_url, expirationDate: expirationDate, state: State.UNFINISHED)
            t.sslVerify = sslVerify
            
            // Check if Firebase has to initialized first
            saveFirebaseConfig(FirebaseConfig(projID: projID, appID: appID, api_key: api_key, projNumber: projNumber))
            loadAndInitFirebase()
            // Add the token and init the push rollout, which gets the FB Token before starting the Push Rollout
            addToken(t)
            initPushRollout(t)
        }
    }
}
