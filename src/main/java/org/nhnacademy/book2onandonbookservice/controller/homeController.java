package org.nhnacademy.book2onandonbookservice.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class homeController {

    @GetMapping("/")
    public String check(){
        return "Server is running why ";
    }

}
