#include <fstream>
#include <string>
#include <iostream>
#include <sstream>
#include <vector>
#include <unordered_map>
#include <functional>
#include <algorithm>
#include <cstdlib>
#include <cstdio>
#include <memory>

// Telegram Bot API
#include <tgbot/tgbot.h>
#include <tgbot/types/Message.h>

// JSON parser
#include <nlohmann/json.hpp>
using json = nlohmann::json;

class Bot 
{
private:
    std::string token;
    TgBot::Bot bot;
    std::vector<int64_t> whitelist = {}; // white list
    std::unordered_map<std::string, std::function<void(TgBot::Message::Ptr, const std::vector<std::string>&)>> commands;

    bool isAllowed(int64_t userId) 
    {
        return std::find(whitelist.begin(), whitelist.end(), userId) != whitelist.end();
    }

    std::vector<std::string> split(const std::string& text)
    {
        std::stringstream ss(text);
        std::string word;
        std::vector<std::string> result;
        while (ss >> word)
            result.push_back(word);
        return result;
    }

    std::string execCommand(const std::string& cmd)
    {
        char buffer[256];
        std::string result;
        std::shared_ptr<FILE> pipe(popen(cmd.c_str(), "r"), pclose);
        if (!pipe) return "";
        while (fgets(buffer, sizeof(buffer), pipe.get()) != nullptr)
            result += buffer;
        return result;
    }

public:
    Bot(const std::string& t) : token(t), bot(t) 
    {
        setupHandlers();
    }

    void setupHandlers()
    {
        commands["/start"] = [this](auto message, auto args)
        {
            bot.getApi().sendMessage(message->chat->id, "HomeBot online!");
        };
		
        commands["/help"] = [this](auto message, auto args)
        {
            std::ifstream file("help.txt");
            if (!file.is_open())
            {
                bot.getApi().sendMessage(message->chat->id,"Help file not found");
                return;
            }
            std::stringstream buffer;
            buffer << file.rdbuf();
            bot.getApi().sendMessage(message->chat->id, buffer.str());
        };

        commands["/poweron"] = [this](auto message, auto args)
        {
            std::system("etherwake -i eth0 00:e0:20:cb:00:13");
            bot.getApi().sendMessage(message->chat->id, "Your PC will turn on soon!");
        };

commands["/download"] = [this](auto message, auto args)
{
    if (args.size() < 2)
    {
        bot.getApi().sendMessage(message->chat->id,
                                 "Usage: /download <URL>\n"
                                 "Supports: YouTube, Instagram, TikTok, SoundCloud, Twitter, etc.");
        return;
    }

    std::string url = args[1];
    std::string downloadDir = "./modules/downloads";

    bot.getApi().sendMessage(message->chat->id, "Downloading...");

    std::string cmd = "./modules/download.sh \"" + url + "\"";
    std::string jsonOutput = execCommand(cmd + " 2>&1");
    
    jsonOutput.erase(0, jsonOutput.find_first_not_of(" \n\r\t"));
    jsonOutput.erase(jsonOutput.find_last_not_of(" \n\r\t") + 1);
    
    if (jsonOutput.empty())
    {
        bot.getApi().sendMessage(message->chat->id, "Download failed!");
        return;
    }

    try
    {
        auto j = json::parse(jsonOutput);
        
        if (j.contains("error"))
        {
            bot.getApi().sendMessage(message->chat->id, 
                "Error: " + j["error"].get<std::string>());
            return;
        }

        std::string videoFile = j["video_path"].get<std::string>();
        std::string audioFile = j["audio_path"].get<std::string>();
        std::string title = j["title"].get<std::string>();
        std::string artist = j["artist"].get<std::string>();
        std::string thumbPath = j["thumb_path"].get<std::string>();
        int duration = j.value("duration", 0);

        if (!videoFile.empty() && access(videoFile.c_str(), F_OK) == 0)
        {
            bot.getApi().sendMessage(message->chat->id, "📹 Sending video...");
            
            try
            {
                auto videoInput = TgBot::InputFile::fromFile(videoFile, "video/mp4");
                
                if (!thumbPath.empty() && access(thumbPath.c_str(), F_OK) == 0)
                {
                    auto thumbInput = TgBot::InputFile::fromFile(thumbPath, "image/jpeg");
                    bot.getApi().sendVideo(
                        message->chat->id,
                        videoInput,
                        false,              // supportsStreaming
                        duration,           // duration
                        0,                  // width
                        0,                  // height
                        thumbInput,         // thumbnail
                        title               // caption
                    );
                }
                else
                {
                    bot.getApi().sendVideo(
                        message->chat->id,
                        videoInput,
                        false,
                        duration,
                        0,
                        0,
                        "", 
                        title
                    );
                }
            }
            catch (std::exception& e)
            {
                bot.getApi().sendMessage(message->chat->id, 
                    "Video send failed: " + std::string(e.what()));
            }
        }

        if (!audioFile.empty() && access(audioFile.c_str(), F_OK) == 0)
        {
            bot.getApi().sendMessage(message->chat->id, "🎵 Sending audio...");
            
            auto audioInput = TgBot::InputFile::fromFile(audioFile, "audio/mpeg");
            
            if (!thumbPath.empty() && access(thumbPath.c_str(), F_OK) == 0)
            {
                auto thumbInput = TgBot::InputFile::fromFile(thumbPath, "image/jpeg");
                bot.getApi().sendAudio(
                    message->chat->id,
                    audioInput,
                    "",
                    duration,
                    artist,
                    title,
                    thumbInput
                );
            }
            else
            {
                bot.getApi().sendAudio(
                    message->chat->id,
                    audioInput,
                    "",
                    duration,
                    artist,
                    title
                );
            }
            
            bot.getApi().sendMessage(message->chat->id, 
                "Done!\n " + title + "\n " + artist);
        }
        else
        {
            bot.getApi().sendMessage(message->chat->id, "❌ No audio/video file found!");
        }
    }
    catch (json::parse_error& e)
    {
        bot.getApi().sendMessage(message->chat->id, 
            "Parse error: " + std::string(e.what()));
    }
    catch (std::exception& e)
    {
        bot.getApi().sendMessage(message->chat->id, 
            "Error: " + std::string(e.what()));
    }

    std::system(("rm -f " + downloadDir + "/*").c_str());
};

        bot.getEvents().onAnyMessage([this](TgBot::Message::Ptr message)
        {
            if (!message->text.empty() && message->from && isAllowed(message->from->id)) {
                auto args = split(message->text);
                if (!args.empty()) {
                    std::string command = args[0];
                    size_t atPos = command.find('@');
                    if (atPos != std::string::npos)
                        command = command.substr(0, atPos);
                    auto it = commands.find(command);
                    if (it != commands.end())
                        it->second(message, args);
                    else
                        bot.getApi().sendMessage(message->chat->id, "Unknown command");
                }
            }
        });
    }

    void run()
    {
        try 
        {
            std::cout << "Bot username: " << bot.getApi().getMe()->username << std::endl;
            TgBot::TgLongPoll longPoll(bot);
            while (true) 
            {
                std::cout << "Long poll started" << std::endl;
                longPoll.start();
            }
        } 
        catch (TgBot::TgException& e) 
        {
            std::cerr << "Error: " << e.what() << std::endl;
        }
    }
};

int main()
{
    Bot myBot(""); // token
    myBot.run();
    return 0;
}
