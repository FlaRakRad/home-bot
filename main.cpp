#include <fstream>
#include <string>
#include <tgbot/tgbot.h>
#include <iostream>
#include <tgbot/types/Message.h>
#include <vector>
#include <unordered_map>
#include <functional>
#include <sstream>
#include <algorithm>
#include <cstdlib>
#include <cstdio>

class Bot 
{
private:
    std::string token;
    TgBot::Bot bot;

    std::vector<int64_t> whitelist = {}; //here is white list of users`s ID

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
            bot.getApi().sendMessage(message->chat->id, "Al is OK");
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

			bot.getApi().sendMessage(message->chat->id,buffer.str());
		};

        commands["/poweron"] = [this](auto message, auto args)
        {
            std::system("tbs");
            bot.getApi().sendMessage(message->chat->id, "Your PC will turn on soon!");
        };

        bot.getEvents().onAnyMessage([this](TgBot::Message::Ptr message)
		{
			if (message->text.empty()) return;
			if (!message->from) return;
			if (!isAllowed(message->from->id)) return;

			auto args = split(message->text);
			if (args.empty()) return;

			std::string command = args[0];
			size_t atPos = command.find('@');
			if (atPos != std::string::npos)
		   command = command.substr(0, atPos);

			auto it = commands.find(command);
			if (it != commands.end())
			it->second(message, args);
			else
	       bot.getApi().sendMessage(message->chat->id, "Unknown command");
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
    Bot myBot(""); //bot`s token
    myBot.run();
    return 0;
}
