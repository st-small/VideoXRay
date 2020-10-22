//
//  ResultsViewController.swift
//  VideoXRay
//
//  Created by Stanly Shiyanovskiy on 22.10.2020.
//

import AVKit
import UIKit

public final class ResultsViewController: UITableViewController {

    // MARK: - Data
    public var movieURL: URL!
    public var predictions: [(time: CMTime, prediction: String)]!

    public override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return predictions.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let prediction = predictions[indexPath.row]
        cell.textLabel?.text = prediction.prediction
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let player = AVPlayer(url: movieURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player

        let prediction = predictions[indexPath.row]
        player.seek(to: prediction.time)

        present(playerViewController, animated: true)
    }
}
